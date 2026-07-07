(* TEST
   subdirectories = "link_lib src";
   setup-ocamlc.byte-build-env;

   {
     flags = "-c -nostdlib -nopervasives";
     module = "link_lib/a.ml";
     ocamlc.byte;
     flags = "-c -nostdlib -nopervasives";
     module = "link_lib/b.ml";
     ocamlc.byte;

     flags = "-c -nostdlib -nopervasives -I link_lib/b.cmi";
     module = "src/uses_b_link.ml";
     ocamlc.byte;

     unset module;
     compile_only = "false";
     flags = "-nostdlib -nopervasives -I link_lib/a.cmo";
     all_modules = "link_lib/a.cmo src/uses_b_link.cmo";
     program = "prog_isolated";
     ocamlc_byte_exit_status = "2";
     ocamlc.byte;
     compiler_reference =
       "${test_source_directory}/test_link_isolation.compilers.reference";
     check-ocamlc.byte-output;
   }
*)
