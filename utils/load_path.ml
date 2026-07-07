(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*                   Jeremie Dimino, Jane Street Europe                   *)
(*                                                                        *)
(*   Copyright 2018 Jane Street Group LLC                                 *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

open Local_store

module STbl = Misc.Stdlib.String.Tbl

(* Mapping from basenames to full filenames *)
type registry = string STbl.t

let visible_files : registry ref = s_table STbl.create 42
let visible_files_uncap : registry ref = s_table STbl.create 42

let hidden_files : registry ref = s_table STbl.create 42
let hidden_files_uncap : registry ref = s_table STbl.create 42

module Dir = struct
  type t =
    | Directory of {
        path : string;
        files : string list;
        hidden : bool;
      }
    | File_entry of {
        parent_dir : string;
        basename : string;
        hidden : bool;
      }

  let path = function
    | Directory d -> d.path
    | File_entry f -> f.parent_dir

  let files = function
    | Directory d -> d.files
    | File_entry f -> [f.basename]

  let hidden = function
    | Directory d -> d.hidden
    | File_entry f -> f.hidden

  let is_file = function
    | Directory _ -> false
    | File_entry _ -> true

  let find t fn =
    match t with
    | Directory d ->
      if List.mem fn d.files then
        Some (Filename.concat d.path fn)
      else
        None
    | File_entry f ->
      if fn = f.basename then
        Some (Filename.concat f.parent_dir fn)
      else
        None

  let find_normalized t fn =
    let fn = Misc.normalized_unit_filename fn in
    match t with
    | Directory d ->
      let search base =
        if Misc.normalized_unit_filename base = fn then
          Some (Filename.concat d.path base)
        else
          None
      in
      List.find_map search d.files
    | File_entry f ->
      if Misc.normalized_unit_filename f.basename = fn then
        Some (Filename.concat f.parent_dir f.basename)
      else
        None

  (* For backward compatibility reason, simulate the behavior of
     [Misc.find_in_path]: silently ignore directories that don't exist
     + treat [""] as the current directory. *)
  let readdir_compat dir =
    try
      Sys.readdir (if dir = "" then Filename.current_dir_name else dir)
    with Sys_error _ ->
      [||]

  let create ~hidden path =
    let path =
      (* For backward compatibility, treat [""] as the current directory,
         like [readdir_compat] does. *)
      if path = "" then Filename.current_dir_name else path
    in
    if Sys.file_exists path then
      if Sys.is_directory path then
        Directory {
          path;
          files = Array.to_list (readdir_compat path);
          hidden;
        }
      else
        File_entry {
          parent_dir = Filename.dirname path;
          basename = Filename.basename path;
          hidden
        }
    else
      (* Backward compatibility: non-existent paths silently produce an
         empty entry.  We cannot distinguish between a non-existent file
         and a non-existent directory, so we treat it as a directory;
         tools may legitimately pre-create include paths before they
         are populated. *)
      Directory { path; files = []; hidden }
end

type auto_include_callback =
  (Dir.t -> string -> string option) -> string -> string

let visible_dirs = s_ref []
let hidden_dirs = s_ref []
let no_auto_include _ _ = raise Not_found
let auto_include_callback = ref no_auto_include

let reset () =
  assert (not Config.merlin || Local_store.is_bound ());
  STbl.clear !hidden_files;
  STbl.clear !hidden_files_uncap;
  STbl.clear !visible_files;
  STbl.clear !visible_files_uncap;
  hidden_dirs := [];
  visible_dirs := [];
  auto_include_callback := no_auto_include

let get_visible () = List.rev !visible_dirs

(* Filter out file-level [-I] entries from path lists.  These entries
   should not appear in directory-level APIs like [get_path_list], which
   consumers such as the C linker, DLL loader, debugger, and .cmt
   metadata use to iterate over include directories. *)
let dir_only_paths dirs =
  List.filter_map
    (function Dir.Directory d -> Some d.path | Dir.File_entry _ -> None)
    dirs
  |> List.rev

let get_path_list () =
  dir_only_paths !visible_dirs @ dir_only_paths !hidden_dirs

type paths =
  { visible : string list;
    hidden : string list }

let get_paths () =
  { visible = dir_only_paths !visible_dirs;
    hidden = dir_only_paths !hidden_dirs }

(* Optimized version of [add] below, for use in [init] and [remove_dir]: since
   we are starting from an empty cache, we can avoid checking whether a unit
   name already exists in the cache simply by adding entries in reverse
   order. *)
let prepend_add dir =
  List.iter (fun base ->
      Result.iter (fun filename ->
          let fn = Filename.concat (Dir.path dir) base in
          if Dir.hidden dir then begin
            STbl.replace !hidden_files base fn;
            STbl.replace !hidden_files_uncap filename fn
          end else begin
            STbl.replace !visible_files base fn;
            STbl.replace !visible_files_uncap filename fn
          end)
        (Misc.normalized_unit_filename base)
    ) (Dir.files dir)

let init ~auto_include ~visible ~hidden =
  reset ();
  visible_dirs := List.rev_map (Dir.create ~hidden:false) visible;
  hidden_dirs := List.rev_map (Dir.create ~hidden:true) hidden;
  List.iter prepend_add !hidden_dirs;
  List.iter prepend_add !visible_dirs;
  auto_include_callback := auto_include

let remove_dir dir =
  assert (not Config.merlin || Local_store.is_bound ());
  let matches d =
    Dir.path d = dir
    || match d with
       | Dir.File_entry f ->
         Filename.concat f.parent_dir f.basename = dir
       | Dir.Directory _ -> false
  in
  let visible = List.filter (fun d -> not (matches d)) !visible_dirs in
  let hidden = List.filter (fun d -> not (matches d)) !hidden_dirs in
  if    List.compare_lengths visible !visible_dirs <> 0
     || List.compare_lengths hidden !hidden_dirs <> 0 then begin
    let saved_auto_include = !auto_include_callback in
    reset ();
    visible_dirs := visible;
    hidden_dirs := hidden;
    List.iter prepend_add hidden;
    List.iter prepend_add visible;
    auto_include_callback := saved_auto_include
  end

(* General purpose version of function to add a new entry to load path: We only
   add a basename to the cache if it is not already present, in order to enforce
   left-to-right precedence. *)
let add (dir : Dir.t) =
  assert (not Config.merlin || Local_store.is_bound ());
  let update base fn visible_files hidden_files =
    if Dir.hidden dir then begin
      if not (STbl.mem !hidden_files base) then
        STbl.replace !hidden_files base fn
    end else if not (STbl.mem !visible_files base) then
      STbl.replace !visible_files base fn
  in
  List.iter
    (fun base ->
       Result.iter (fun ubase ->
           let fn = Filename.concat (Dir.path dir) base in
           update base fn visible_files hidden_files;
           update ubase fn visible_files_uncap hidden_files_uncap
         )
         (Misc.normalized_unit_filename base)
    )
    (Dir.files dir);
  if Dir.hidden dir then
    hidden_dirs := dir :: !hidden_dirs
  else
    visible_dirs := dir :: !visible_dirs

let append_dir = add

let add_dir ~hidden dir = add (Dir.create ~hidden dir)

(* Add the directory at the start of load path - so basenames are
   unconditionally added. *)
let prepend_dir (dir : Dir.t) =
  assert (not Config.merlin || Local_store.is_bound ());
  prepend_add dir;
  if Dir.hidden dir then
    hidden_dirs := !hidden_dirs @ [dir]
  else
    visible_dirs := !visible_dirs @ [dir]

let is_basename fn = Filename.basename fn = fn

let auto_include_libs libs alert find_in_dir fn =
  let scan (lib, lazy dir) =
    let file = find_in_dir dir fn in
    let alert_and_add_dir _ =
      alert lib;
      append_dir dir
    in
    Option.iter alert_and_add_dir file;
    file
  in
  match List.find_map scan libs with
  | Some base -> base
  | None -> raise Not_found

let auto_include_otherlibs =
  (* Ensure directories are only ever scanned once *)
  let expand = Misc.expand_directory Config.standard_library in
  let otherlibs =
    let read_lib lib = lazy (Dir.create ~hidden:false (expand ("+" ^ lib))) in
    List.map (fun lib -> (lib, read_lib lib)) ["dynlink"; "str"; "unix"] in
  auto_include_libs otherlibs

type visibility = Visible | Hidden

let find_file_in_cache fn visible_files hidden_files =
  try (STbl.find !visible_files fn, Visible) with
  | Not_found -> (STbl.find !hidden_files fn, Hidden)

let find fn =
  assert (not Config.merlin || Local_store.is_bound ());
  try
    if is_basename fn then
      fst (find_file_in_cache fn visible_files hidden_files)
    else
      Misc.find_in_path
        (dir_only_paths !visible_dirs @ dir_only_paths !hidden_dirs) fn
  with Not_found ->
    !auto_include_callback Dir.find fn

let find_normalized_with_visibility fn =
  assert (not Config.merlin || Local_store.is_bound ());
  match Misc.normalized_unit_filename fn with
  | Error _ -> raise Not_found
  | Ok fn_uncap ->
  try
    if is_basename fn then
      find_file_in_cache fn_uncap
        visible_files_uncap hidden_files_uncap
    else
      try
        (Misc.find_in_path_normalized
           (dir_only_paths !visible_dirs) fn, Visible)
      with
      | Not_found ->
        (Misc.find_in_path_normalized
           (dir_only_paths !hidden_dirs) fn, Hidden)
  with Not_found ->
    (!auto_include_callback Dir.find_normalized fn_uncap, Visible)

let find_normalized fn = fst (find_normalized_with_visibility fn)
