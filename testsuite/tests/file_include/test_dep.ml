(* TEST
(* ocamldep with file -I triggers a documented limitation *)


subdirectories = "lib_only_mli src";
setup-ocamlc.byte-build-env;

{
  flags = "-c -nostdlib -nopervasives";
  module = "lib_only_mli/a.mli";
  ocamlc.byte;

  (* ocamldep uses its own path handling (makedepend.ml), not Load_path;
     file -I triggers "Bad -I option" *)
  commandline = "-depend -I lib_only_mli/a.cmi src/b.ml";
  ocamlc_byte_exit_status = "2";
  ocamlc.byte;
  compiler_reference =
    "${test_source_directory}/ocamldep_file_I.compilers.reference";
  check-ocamlc.byte-output;
}

*)
