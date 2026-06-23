(* Smoke test for the OCaml test provider port. Prints summary stats that must
 * match the canonical TS output documented in PROVIDER work.
 *
 * NOTE: NOT compiled/run — the OCaml toolchain is unavailable in the authoring
 * environment. Self-reviewed against the canonical ts/provider.ts. *)

open Provider

(* Render an expect_kind / input_kind as its canonical lowercase tag. *)
let expect_kind_str = function
  | `Value -> "value"
  | `Error -> "error"
  | `Match -> "match"
  | `Absent -> "absent"

let input_kind_str = function `In -> "in" | `Args -> "args" | `Ctx -> "ctx"

(* Count occurrences, preserving a fixed display order. *)
let count_in_order order tbl =
  List.filter_map
    (fun k -> match List.assoc_opt k tbl with Some c when c > 0 -> Some (k, c) | _ -> None)
    order

let bump tbl k =
  let cur = match List.assoc_opt k !tbl with Some c -> c | None -> 0 in
  tbl := (k, cur + 1) :: List.remove_assoc k !tbl

let () =
  let prov = load () in

  let fns = functions prov in
  Printf.printf "functions: %s\n" (String.concat ", " fns);

  let total = ref 0 in
  let expect_kinds = ref [] in
  let input_kinds = ref [] in
  List.iter
    (fun fn ->
      List.iter
        (fun e ->
          incr total;
          bump expect_kinds (expect_kind_str e.expect.ekind);
          bump input_kinds (input_kind_str e.input.kind))
        (entries prov fn))
    fns;

  Printf.printf "total entries: %d\n" !total;

  (* Fixed order to match the documented expected line. *)
  let ek = count_in_order [ "value"; "absent"; "match"; "error" ] !expect_kinds in
  Printf.printf "expect kinds: %s\n"
    (String.concat ", " (List.map (fun (k, c) -> Printf.sprintf "%s=%d" k c) ek));

  let ik = count_in_order [ "in"; "args"; "ctx" ] !input_kinds in
  Printf.printf "input kinds: %s\n"
    (String.concat ", " (List.map (fun (k, c) -> Printf.sprintf "%s=%d" k c) ik));

  let e = List.hd (entries ~group:"basic" prov "getpath") in
  let id_str = match e.id with Some s -> s | None -> "null" in
  let value_str =
    match e.expect.value with Some v -> stringify v | None -> "null"
  in
  Printf.printf
    "getpath/basic[0]: id=%s, doc=%b, input.kind=%s, expect.kind=%s, expect.value=%s\n"
    id_str e.doc
    (input_kind_str e.input.kind)
    (expect_kind_str e.expect.ekind)
    value_str;

  (* ---- helper sanity checks ---- *)
  Printf.printf "equal(Null, Null) lenient: %b\n" (equal Null Null);
  Printf.printf "equal_strict(Null, __NULL__): %b / equal_strict(Null, 1): %b\n"
    (equal_strict Null (Str nullmark))
    (equal_strict Null (Num 1.0));
  Printf.printf "error_matches substring ci: %b\n"
    (error_matches { any = false; text = Some "Foo"; regex = false } "a foobar error");
  let sm =
    struct_match (Obj [ ("a", Obj [ ("b", Num 2.0) ]) ]) (Obj [ ("a", Obj [ ("b", Num 3.0) ]) ])
  in
  Printf.printf "struct_match failure: {ok=%b, path=%s, expected=%s, actual=%s}\n"
    sm.ok
    (String.concat "/" sm.path)
    (match sm.expected with Some v -> stringify v | None -> "")
    (match sm.actual with Some v -> stringify v | None -> "")
