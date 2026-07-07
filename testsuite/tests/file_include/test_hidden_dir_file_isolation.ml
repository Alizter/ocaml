(* TEST
   subdirectories = "twolibs src";
   setup-ocamlc.byte-build-env;

   {
     flags = "-c -nostdlib -nopervasives";
     module = "twolibs/a.mli";
     ocamlc.byte;
     flags = "-c -nostdlib -nopervasives";
     module = "twolibs/b.mli";
     ocamlc.byte;

     flags = "-c -nostdlib -nopervasives -H twolibs/ -I twolibs/a.cmi";
     module = "src/uses_b.ml";
     ocamlc_byte_exit_status = "2";
     ocamlc.byte;
     compiler_reference =
       "${test_source_directory}/test_hidden_dir_file_isolation.compilers.reference";
     check-ocamlc.byte-output;
   }
*)
