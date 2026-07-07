(* TEST
   subdirectories = "lib_a lib_b src";
   setup-ocamlc.byte-build-env;

   {
     flags = "-c -nostdlib -nopervasives";
     module = "lib_a/a.mli";
     ocamlc.byte;
     flags = "-c -nostdlib -nopervasives -H lib_a/a.cmi";
     module = "lib_b/b.mli";
     ocamlc.byte;

     flags = "-c -nostdlib -nopervasives -H lib_a/a.cmi -I lib_b/";
     module = "src/uses_a_direct.ml";
     ocamlc_byte_exit_status = "2";
     ocamlc.byte;
     compiler_reference =
       "${test_source_directory}/test_hidden_module_reject.compilers.reference";
     check-ocamlc.byte-output;
   }
*)
