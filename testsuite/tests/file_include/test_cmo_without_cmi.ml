(* TEST
   subdirectories = "lib src";
   setup-ocamlc.byte-build-env;

   {
     flags = "-c -nostdlib -nopervasives";
     module = "lib/a.ml";
     ocamlc.byte;

     flags = "-c -nostdlib -nopervasives -I lib/a.cmo";
     module = "src/b.ml";
     ocamlc_byte_exit_status = "2";
     ocamlc.byte;
     compiler_reference =
       "${test_source_directory}/test_cmo_without_cmi.compilers.reference";
     check-ocamlc.byte-output;
   }
*)
