(* TEST
(* ====================================================================
   Tests for file-level -I / -H (passing a .cmi/.cmo/.cmx file).

   This test exercises the compiler's ability to accept individual
   compilation artifacts as -I/-H arguments, registering only that
   single file rather than the entire containing directory.

   Library layout
   ==============
   lib/               module A (v : int)
   lib_v1/            alternate A (v : int)
   lib_v2/            alternate A (v : string); also module B
   twolibs/           modules A and B sharing a directory (isolation tests)
   lib_a/             module A for hidden-include (-H) tests
   lib_b/             module B that depends on A (lib_b/b.mli uses A)
   link_lib/          modules A and B for link-time isolation
   lib_only_mli_src/  consumer of lib_only_mli (uses A via .cmi-only file-I)
   lib_only_mli/      module A (only .mli, no .ml); tests .cmi-only registration
   looks_like_cmi/    a directory whose name ends in .cmi; must be treated
                      as a regular directory, not a file entry
   pack_units/        sub.ml using A for -pack tests

   Consumers under src/
   ====================
   lib_only_mli_src/use_a.ml  `let y = A.x`          (uses A via .cmi-only file-I)
   b.ml                `let y = A.x`          (uses A)
   uses_a.ml           `let y = A.x`          (uses A)
   uses_b.ml           `let _ = B.b`          (uses B, expects failure when isolated)
   uses_b_link.ml      `let _ = B.b`          (uses B, link-time isolation)
   uses_b_trans.ml     `let z = B.b`          (uses B transitively via -H)
   uses_a_direct.ml    `let y = A.x`          (uses A directly, expects failure under -H)
   uses_a_string.ml    `let y = A.v`          (uses A, expects v : string from lib_v2)
   use_foo.ml          `let y = Foo.x`        (uses Foo, lowercased .cmi name)
   c_uses_both.ml      `let z = A.v + B.b`    (uses A and B from different dirs)
   c_uses_a_string.ml  `let z = A.v ^ \"!\"`   (uses A, expects string)
   empty.ml            empty module (smoke tests)

   (* Deferred: symlink tests need shell actions *)
   (* Deferred: ocamldep with file -I, handled in test_dep.ml *)
   (* Deferred: +prefix tests need stdlib scaffolding *)
   ==================================================================== *)

subdirectories = "lib src twolibs lib_v1 lib_v2 looks_like_cmi lib_a lib_b link_lib pack_units lib_only_mli lib_only_mli_src";
setup-ocamlc.byte-build-env;

(* ====================================================================
   Basic compilation
   ==================================================================== *)

(* Basic compilation with a single .cmi file *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib_only_mli/a.mli";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I lib_only_mli/a.cmi";
  module = "lib_only_mli_src/use_a.ml";
  ocamlc.byte;
}

(* Linking succeeds with file-level -I pointing to a .cmo *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib/a.ml";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I lib/a.cmi";
  module = "src/b.ml";
  ocamlc.byte;

  unset module;
  compile_only = "false";
  flags = "-nostdlib -nopervasives -I lib/a.cmo";
  all_modules = "lib/a.cmo src/b.cmo";
  program = "prog_basic_cmo";
  ocamlc.byte;
}

(* Both .cmi and .cmo registered, full separate compilation and linking *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib/a.ml";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I lib/a.cmi";
  module = "src/b.ml";
  ocamlc.byte;

  unset module;
  compile_only = "false";
  flags = "-nostdlib -nopervasives -I lib/a.cmi -I lib/a.cmo";
  all_modules = "lib/a.cmo src/b.cmo";
  program = "prog_basic_cmi_cmo";
  ocamlc.byte;
}

(* Cross-module optimization via file-level -I with ocamlopt *)
{
  setup-ocamlopt.byte-build-env;

  flags = "-c -nostdlib -nopervasives";
  module = "lib/a.ml";
  ocamlopt.byte;

  flags = "-c -nostdlib -nopervasives -I lib/a.cmi -I lib/a.cmx";
  module = "src/b.ml";
  ocamlopt.byte;
}

(* ====================================================================
   Isolation: file -I does not leak sibling modules
   ==================================================================== *)

(* Compile-time isolation: -I twolibs/a.cmi does not expose twolibs/b.cmi *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "twolibs/a.mli";
  ocamlc.byte;
  flags = "-c -nostdlib -nopervasives";
  module = "twolibs/b.mli";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I twolibs/a.cmi";
  module = "src/uses_b.ml";
  ocamlc_byte_exit_status = "2";
  ocamlc.byte;
  compiler_reference =
    "${test_source_directory}/isolation_error.compilers.reference";
  check-ocamlc.byte-output;
}

(* ====================================================================
   File -I interaction with directory -I / -H
   ==================================================================== *)

(* File -I composes with directory -I *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib_v1/a.mli";
  ocamlc.byte;
  flags = "-c -nostdlib -nopervasives";
  module = "lib_v2/a.mli";
  ocamlc.byte;
  flags = "-c -nostdlib -nopervasives";
  module = "lib_v2/b.mli";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I lib_v1/a.cmi -I lib_v2/";
  module = "src/c_uses_both.ml";
  ocamlc.byte;
}

(* Earlier directory -I wins over later file -I *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib_v1/a.mli";
  ocamlc.byte;
  flags = "-c -nostdlib -nopervasives";
  module = "lib_v2/a.mli";
  ocamlc.byte;
  flags = "-c -nostdlib -nopervasives";
  module = "lib_v2/b.mli";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I lib_v2/ -I lib_v1/a.cmi";
  module = "src/c_uses_a_string.ml";
  ocamlc.byte;
}

(* -I and -H given the same file: -I wins, file is visible *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib_only_mli/a.mli";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I lib_only_mli/a.cmi -H lib_only_mli/a.cmi";
  module = "lib_only_mli_src/use_a.ml";
  ocamlc.byte;
}

(* -H and -I given the same file: -I wins regardless of order *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib_only_mli/a.mli";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -H lib_only_mli/a.cmi -I lib_only_mli/a.cmi";
  module = "lib_only_mli_src/use_a.ml";
  ocamlc.byte;
}

(* -H dir/ combined with -I dir/file.cmi: file visible, rest of dir hidden *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "twolibs/a.mli";
  ocamlc.byte;
  flags = "-c -nostdlib -nopervasives";
  module = "twolibs/b.mli";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -H twolibs/ -I twolibs/a.cmi";
  module = "src/uses_a.ml";
  ocamlc.byte;
}

(* -I dir/ combined with -H dir/file.cmi: everything visible, -I dir wins *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "twolibs/a.mli";
  ocamlc.byte;
  flags = "-c -nostdlib -nopervasives";
  module = "twolibs/b.mli";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I twolibs/ -H twolibs/a.cmi";
  module = "src/uses_b.ml";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I twolibs/ -H twolibs/a.cmi";
  module = "src/uses_a.ml";
  ocamlc.byte;
}

(* Two file-level -I for the same module from different dirs: earlier wins *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib_v1/a.mli";
  ocamlc.byte;
  flags = "-c -nostdlib -nopervasives";
  module = "lib_v2/a.mli";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I lib_v1/a.cmi -I lib_v2/a.cmi";
  module = "src/uses_a.ml";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I lib_v2/a.cmi -I lib_v1/a.cmi";
  module = "src/c_uses_a_string.ml";
  ocamlc.byte;
}

(* File-I and dir-I for the same module from different locations: earlier wins *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib_v1/a.mli";
  ocamlc.byte;
  flags = "-c -nostdlib -nopervasives";
  module = "lib_v2/a.mli";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I lib_v1/a.cmi -I lib_v2/";
  module = "src/uses_a.ml";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I lib_v2/ -I lib_v1/a.cmi";
  module = "src/c_uses_a_string.ml";
  ocamlc.byte;
}

(* Transitive availability through -H *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib_a/a.mli";
  ocamlc.byte;
  flags = "-c -nostdlib -nopervasives -I lib_a/";
  module = "lib_b/b.mli";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -H lib_a/a.cmi -I lib_b/";
  module = "src/uses_b_trans.ml";
  ocamlc.byte;
}

(* ====================================================================
   Edge cases
   ==================================================================== *)

(* Nonexistent file is silently ignored with -I *)
{
  flags = "-c -nostdlib -nopervasives -I nonexistent.cmi";
  module = "src/empty.ml";
  ocamlc.byte;
}

(* Nonexistent file is silently ignored with -H *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib/a.ml";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -H nonexistent.cmi -I lib/";
  module = "src/b.ml";
  ocamlc.byte;
}

(* Directory whose name ends in .cmi is treated as a regular directory *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "looks_like_cmi/a.mli";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I looks_like_cmi";
  module = "src/uses_a.ml";
  ocamlc.byte;
}

(* Arbitrary file extension is accepted as a harmless file entry *)
{
  flags = "-c -nostdlib -nopervasives -I lib/arbitrary.txt";
  module = "src/empty.ml";
  ocamlc.byte;
}

(* Current-directory file with ./ prefix *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib/a.ml";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I ./lib/a.cmi";
  module = "src/b.ml";
  ocamlc.byte;
}

(* Passing the same file twice is idempotent *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib/a.ml";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I lib/a.cmi -I lib/a.cmi";
  module = "src/b.ml";
  ocamlc.byte;
}

(* Lowercase filename resolves capitalized module name *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib/foo.mli";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I lib/foo.cmi";
  module = "src/use_foo.ml";
  ocamlc.byte;
}

(* Absolute path *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib/a.ml";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I ${test_build_directory}/lib/a.cmi";
  module = "src/b.ml";
  ocamlc.byte;
}

(* Two different string paths to the same file (-I ./lib/a.cmi -I lib/a.cmi) *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib/a.ml";
  ocamlc.byte;

  (* Both paths resolve to the same underlying file; second
     entry overwrites the first, same effective registration. *)
  flags = "-c -nostdlib -nopervasives -I ./lib/a.cmi -I lib/a.cmi";
  module = "src/b.ml";
  ocamlc.byte;
}

(* ====================================================================
   Advanced linking
   ==================================================================== *)

(* ocamlopt -pack with file-level -I *)
{
  setup-ocamlopt.byte-build-env;

  flags = "-c -nostdlib -nopervasives -for-pack Packed";
  module = "lib/a.ml";
  ocamlopt.byte;

  flags = "-c -nostdlib -nopervasives -for-pack Packed -I lib/a.cmi -I lib/a.cmx";
  module = "pack_units/sub.ml";
  ocamlopt.byte;

  unset module;
  program = "packed.cmx";
  flags = "-pack -nostdlib -nopervasives -I lib/a.cmx";
  all_modules = "pack_units/sub.cmx lib/a.cmx";
  ocamlopt.byte;
}

(* ocamlc -a (library creation) with file-level -I *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "link_lib/a.ml";
  ocamlc.byte;

  unset module;
  compile_only = "false";
  flags = "-a -nostdlib -nopervasives -I link_lib/a.cmo";
  all_modules = "link_lib/a.cmo";
  program = "mylib.cma";
  ocamlc.byte;
}

(* ====================================================================
   Regression
   ==================================================================== *)

(* Directory -I still works identically *)
{
  flags = "-c -nostdlib -nopervasives";
  module = "lib/a.ml";
  ocamlc.byte;

  flags = "-c -nostdlib -nopervasives -I lib/";
  module = "src/b.ml";
  ocamlc.byte;
}

*)
