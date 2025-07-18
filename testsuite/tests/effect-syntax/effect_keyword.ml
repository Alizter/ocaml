(* TEST
 expect;
*)

module M = struct
  effect A
  type 'a eff += A_
  effect B of int
  type 'a eff += B_ of int
  effect C : int -> string eff
  type 'a eff += C_ : int -> string eff
end
[%%expect {|
module M :
  sig
    type 'a eff += A
    type 'a eff += A_
    type 'a eff += B of int
    type 'a eff += B_ of int
    type 'a eff += C : int -> string eff
    type 'a eff += C_ : int -> string eff
  end
|}]

module type S = sig
  effect A
  effect B of int
  effect C : int -> string eff
end
[%%expect {|
module type S =
  sig
    type 'a eff += A
    type 'a eff += B of int
    type 'a eff += C : int -> string eff
  end
|}]

let local () =
  let effect A in
  let effect B of int in
  let effect C : int -> string eff in
  Effect.perform A;
  Effect.perform (B 42);
  Effect.perform (C 99)
[@@warning "-21"]
[%%expect{|
val local : unit -> string = <fun>
|}]

(* TODO: Fix *)
module M_decl = struct
  include (M : S)
  effect A_ = A
  effect B_ = B
  effect C_ = C
end
[%%expect{|
Line 5, characters 14-15:
5 |   effect C_ = C
                  ^
Error: The constructor "C" extends type "eff" whose declaration does not match
       the declaration of type "eff"
|}]
