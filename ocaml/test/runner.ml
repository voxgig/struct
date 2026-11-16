(* The shared corpus, run on the shared runner.
 *
 * The in-situ runner - a JSON reader, `fix_json`, `eqv`, `do_match`,
 * `matchval`, `resolve_args`, `check_result` and `handle_error`, all of it
 * this port's own copy of omni's algorithm - is gone. Every group is driven
 * through voxgig/omni, so this file only says WHICH subject answers each group
 * and with which flags.
 *
 * omni is consumed as a local checkout: the Makefile finds it via $OMNI_HOME
 * or beside this repository and compiles `omni.ml` in with the tests. Only the
 * tests use it - `make build` compiles src/ alone (register 4.13).
 *
 * Flags mirror canonical: typescript/test/utility/StructUtility.test.ts. *)

open Voxgig_struct

module O = Omni

let nullmark = "__NULL__"
let undefmark = "__UNDEF__"
let existsmark = "__EXISTS__"

let _ = undefmark
let _ = existsmark

(* ---------------- the bridge ---------------- *)

(* omni's model -> this port's. Both draw the same absent/null/value
   distinction, so nothing is guessed. *)
let rec tostruct (value : O.json) : value =
  match value with
  | O.Absent -> Noval
  | O.Null -> Null
  | O.Bool b -> Bool b
  | O.Num n -> Num n
  | O.Str s -> Str s
  | O.JList items -> lst (List.map tostruct items)
  | O.JMap entries ->
    let m = empty_map () in
    List.iter (fun (k, v) -> ignore (setprop m (Str k) (tostruct v))) entries;
    m

(* This port's model -> omni's. A function or a sentinel has no JSON form and
   omni only ever stringifies one, so it becomes its own rendering rather than
   silently collapsing to null. *)
let rec toomni (value : value) : O.json =
  match value with
  | Noval -> O.Absent
  | Null -> O.Null
  | Bool b -> O.Bool b
  | Num n -> O.Num n
  | Str s -> O.Str s
  | List items -> O.JList (List.map toomni !items)
  | Map m -> O.JMap (List.map (fun (k, v) -> (k, toomni v)) m.entries)
  | Func _ -> O.Str "[Function]"
  | Sentinel tag -> O.Str ("`$" ^ tag ^ "`")

(* Order-independent deep equality, through omni's own rule so the hand-written
   cases below compare the way every group does. *)
let eqv a b = O.deepequal (toomni a) (toomni b)

let omap_v kvs =
  let m = empty_map () in
  List.iter (fun (k, v) -> ignore (setprop m (Str k) v)) kvs;
  m

let getprop_raw_pub e k =
  match e with Map m -> (match omap_get m k with Some x -> x | None -> Noval) | _ -> Noval

(* ---------------- result tracking ---------------- *)

let npass = ref 0
let nfail = ref 0
let failures = ref []

let record group ok msg =
  if ok then incr npass
  else (incr nfail; failures := Printf.sprintf "FAIL %s - %s" group msg :: !failures)

let runpack : O.runpack option ref = ref None

let pack () = match !runpack with Some p -> p | None -> failwith "runner not started"

(* ---------------- running a group ---------------- *)

(* Each group is one assertion: omni stops at its first failing entry and
   reports the index, the entry and both values.

   The subject is handed omni's arguments as an ARRAY it may overwrite, and
   the wrapper writes the converted argument back - `match.args` asserts an
   in-place rewrite in eight of `minor/setpath`'s nine entries and all six of
   `merge/integrity`, and this port's nodes are mutable while omni's json is
   not. cpp and rust needed the same entry point for the same reason. *)
let run_set ?(flags = []) group node subject =
  let donull = match List.assoc_opt "null" flags with Some b -> b | None -> true in
  let useflags = { O.null = donull; name = Some group } in
  let call cells =
    let args = Array.to_list cells |> List.map tostruct in
    let res = subject args in
    List.iteri (fun index arg -> cells.(index) <- toomni arg) args;
    toomni res
  in
  match (pack ()).O.runsetflags_args (toomni node) useflags call with
  | () -> record group true ""
  | exception O.Omni_error message -> record group false message
  | exception Struct_error message -> record group false message
  | exception err -> record group false (Printexc.to_string err)

(* `merge.basic`, `inject.basic` and `transform.basic` are single entries, not
   sets, so the runner cannot drive them. Compared here, through omni's own
   deepequal so the rule is the one every group uses. *)
let run_single group node actual_fn =
  match actual_fn (getprop_raw_pub node "in") with
  | actual ->
    if O.deepequal (toomni (getprop_raw_pub node "out")) (toomni actual) then record group true ""
    else
      record group false
        (Printf.sprintf "Expected: %s, got: %s" (stringify (getprop_raw_pub node "out"))
           (stringify actual))
  | exception Struct_error message -> record group false message
  | exception err -> record group false (Printexc.to_string err)

(* ---------------- arg helpers ---------------- *)

let arg1 f = fun args -> f (match args with x :: _ -> x | [] -> Noval)
let vget vin k = match vin with Map m -> (match omap_get m k with Some x -> x | None -> Noval) | _ -> Noval
let vhas vin k = match vin with Map m -> omap_has m k | _ -> false

let default_injdef_pub () =
  { d_meta = Noval; d_extra = Noval; d_errs = Noval; d_modify = None; d_handler = None;
    d_base = Noval; d_dparent = Noval; d_dpath = Noval; d_key = Noval }

(* ---------------- test groups ---------------- *)

let null_modifier v key parent _inj =
  if v = Str nullmark then ignore (setprop parent key Null)
  else (match v with Str s -> ignore (setprop parent key (Str (
      (* replace __NULL__ with null *)
      let b = Buffer.create (String.length s) in
      let nl = String.length nullmark in let n = String.length s in let i = ref 0 in
      while !i < n do
        if !i + nl <= n && String.sub s !i nl = nullmark then (Buffer.add_string b "null"; i := !i + nl)
        else (Buffer.add_char b s.[!i]; incr i)
      done; Buffer.contents b)))
   | _ -> ())

(* ---------------- condense: what the corpus cannot express ---------------- *)

(* Identity, sharing and the immutability contract, as canonical's
   `condense-*` tests check them. *)

let expect ok what = if not ok then failwith what

let run_local group f =
  match f () with
  | () -> record group true ""
  | exception Failure message -> record group false message
  | exception Struct_error message -> record group false message
  | exception err -> record group false (Printexc.to_string err)

let contains s sub =
  let n = String.length s and m = String.length sub in
  let rec at i = i + m <= n && (String.sub s i m = sub || at (i + 1)) in
  at 0

let raises_immutable f =
  match f () with
  | _ -> false
  | exception Struct_error message -> contains message "immutable"

let node_count c = size (getprop_raw_pub c "node")

let compact v = jsonify ~flags:(jm [Str "indent"; Num 0.0]) v

let run_condense_local () =
  run_local "condense.deterministic" (fun () ->
      let src = jm [Str "b"; jm [Str "m"; Str "GET"]; Str "a"; jm [Str "m"; Str "GET"];
                    Str "l"; jt [Num 1.0; Str "x"; Bool true]] in
      expect (compact (condense src) = compact (condense src)) "condense is not deterministic";
      let reordered = jm [Str "l"; jt [Num 1.0; Str "x"; Bool true]; Str "a"; jm [Str "m"; Str "GET"];
                          Str "b"; jm [Str "m"; Str "GET"]] in
      expect (compact (condense src) = compact (condense reordered))
        "insertion order changed the bytes");

  run_local "condense.shares-identical-subtrees" (fun () ->
      let one = condense (jm [Str "x"; jm [Str "m"; Str "GET"; Str "p"; Str "/1"]]) in
      let two = condense (jm [Str "x"; jm [Str "m"; Str "GET"; Str "p"; Str "/1"];
                              Str "y"; jm [Str "m"; Str "GET"; Str "p"; Str "/1"]]) in
      expect (node_count two = node_count one) "a second identical subtree added nodes";
      let three = condense (jm [Str "x"; jm [Str "m"; Str "GET"]; Str "y"; jm [Str "m"; Str "PUT"];
                                Str "z"; jm [Str "m"; Str "POST"]]) in
      expect (node_count three > node_count two) "distinct subtrees added no nodes");

  run_local "condense.round-trips-by-value" (fun () ->
      let src = jm [Str "a"; jm [Str "b"; jt [Num 1.0; Str "x"; Bool true; Null; empty_map ()]];
                    Str "c"; Str "z"] in
      expect (eqv (expand (condense src)) src) "expand did not give back the value");

  run_local "condense.getpath-is-transparent" (fun () ->
      let src = jm [Str "entity"; jm [Str "p"; jm [Str "op"; jm [Str "list"; jm [Str "method"; Str "GET"]]]]] in
      let c = condense src in
      let path = jt [Str "entity"; Str "p"; Str "op"; Str "list"] in
      expect (eqv (getpath c path) (getpath src path)) "a node read differs";
      expect (getpath c (jt [Str "entity"; Str "p"; Str "op"; Str "list"; Str "method"]) = Str "GET")
        "a leaf read differs";
      expect (getpath c (jt [Str "entity"; Str "nope"]) = Noval) "a miss is not absent");

  run_local "condense.view-reads-without-materialising" (fun () ->
      let c = condense (jm [Str "entity"; jm [Str "a"; jm [Str "v"; Num 1.0]; Str "b"; jm [Str "v"; Num 2.0]];
                            Str "other"; Num 9.0]) in
      let v = condenseview c in
      expect (v#keys (Str "entity") = ["a"; "b"]) "keys";
      expect (((v#at (Str "entity"))#at (Str "b"))#get (Str "v") = Num 2.0) "at then get";
      expect (v#has (Str "entity.a")) "has entity.a";
      expect (not (v#has (Str "entity.zz"))) "has entity.zz";
      expect (v#size = 2) "size");

  run_local "condense.value-copies-and-ref-shares" (fun () ->
      let c = condense (jm [Str "a"; jm [Str "m"; Str "GET"]; Str "b"; jm [Str "m"; Str "GET"]]) in
      let v = condenseview c in
      (* a and b share one node; get must not let that be observed. *)
      let x = v#get (Str "a") in
      let y = v#get (Str "b") in
      expect (eqv x y) "a and b differ";
      expect (x != y) "get handed out one node twice";
      ignore (setprop x (Str "m") (Str "MUTATED"));
      expect (getprop (v#get (Str "b")) (Str "m") = Str "GET") "a mutation reached another read";
      expect ((v#at (Str "a"))#ref == (v#at (Str "a"))#ref) "ref did not share");

  run_local "condense.preserves-proto-named-keys-and-values" (fun () ->
      let as_value = jm [Str "x"; Str "__proto__"] in
      expect (eqv (expand (condense as_value)) as_value) "a value named __proto__";
      let as_key = jm [Str "__proto__"; Num 1.0] in
      expect (compact (expand (condense as_key)) = "{\"__proto__\":1}") "a key named __proto__");

  run_local "condense.getpath-matches-plain-on-null-and-options" (fun () ->
      expect (getpath (condense (jm [Str "a"; Null])) (Str "a") = getpath (jm [Str "a"; Null]) (Str "a"))
        "a stored null reads differently";
      expect (getpath (condense (jm [Str "a"; Null])) (Str "a") = Noval) "a stored null is not absent";
      let store = jm [Str "base"; jm [Str "x"; Num 1.0]] in
      let d = { (default_injdef_pub ()) with d_base = Str "base" } in
      expect (getpath ~inj:(IDef d) (condense store) (Str "x") = getpath ~inj:(IDef d) store (Str "x"))
        "base was ignored");

  (* Unary + would accept these; an ordinary list lookup does not, so
     condensing must not change which value a path selects. *)
  run_local "condense.list-keys-are-canonical-integers" (fun () ->
      let plain = jm [Str "l"; jt [Num 10.0; Num 20.0]] in
      let c = condense plain in
      List.iter (fun k ->
          let path = jt [Str "l"; Str k] in
          expect (getpath c path = getpath plain path) ("list key " ^ k))
        ["01"; "1e0"; " 1"; "+1"; "1.0"; "-0"];
      expect (getpath c (jt [Str "l"; Str "1"]) = Num 20.0) "list key 1");

  run_local "condense.symbols-sort-by-code-point" (fun () ->
      let ffff = "\xef\xbf\xbf" and astral = "\xf0\x90\x80\x80" in
      let sym = getprop_raw_pub (condense (jm [Str "a"; Str astral; Str "b"; Str ffff])) "sym" in
      let rec position x i = function
        | [] -> -1
        | y :: rest -> if y = x then i else position x (i + 1) rest in
      let syms = (match sym with List r -> !r | _ -> []) in
      let p_ffff = position (Str ffff) 0 syms and p_astral = position (Str astral) 0 syms in
      expect (0 <= p_ffff && p_ffff < p_astral)
        ("symbol table is not in code-point order: " ^ compact sym));

  run_local "condense.astral-keys-resolve" (fun () ->
      let fullwidth = "\xef\xbc\xa1" and grin = "\xf0\x9f\x98\x80" in
      let c = condense (jm [Str fullwidth; Num 1.0; Str grin; Num 2.0]) in
      expect (getpath c (jt [Str grin]) = Num 2.0) "the astral key";
      expect (getpath c (jt [Str fullwidth]) = Num 1.0) "the BMP key";
      expect ((condenseview c)#get (Str grin) = Num 2.0) "the astral key through a view");

  run_local "condense.invalid-key-mutations-stay-no-ops" (fun () ->
      let c = condense (jm [Str "a"; Num 1.0]) in
      expect (delprop c Noval == c) "delprop with an invalid key";
      expect (setprop c Noval (Num 1.0) == c) "setprop with an invalid key";
      expect (raises_immutable (fun () -> delprop c (Str "sym"))) "a valid delprop did not raise");

  run_local "condense.is-immutable" (fun () ->
      let c = condense (jm [Str "a"; Num 1.0]) in
      expect (raises_immutable (fun () -> setpath c (Str "a") (Num 2.0))) "setpath";
      expect (raises_immutable (fun () -> setprop c (Str "a") (Num 2.0))) "setprop";
      expect (raises_immutable (fun () -> delprop c (Str "sym"))) "delprop";
      let e = expand c in
      ignore (setpath e (Str "a") (Num 2.0));
      expect (getprop e (Str "a") = Num 2.0) "the expanded copy is not mutable")

let rec run_all spec =
  let g k = getprop_raw_pub spec k in
  ignore g;
  let minor = g "minor" and walks = g "walk" and merges = g "merge"
  and getpaths = g "getpath" and injects = g "inject" and transforms = g "transform"
  and validates = g "validate" and selects = g "select" and sentinels = g "sentinels" in
  let mg n = getprop_raw_pub minor n in

  (* condense *)
  let condenses = g "condense" in
  run_set "condense.condense" ~flags:["null", false] (getprop_raw_pub condenses "condense")
    (arg1 condense);
  run_set "condense.expand" ~flags:["null", false] (getprop_raw_pub condenses "expand")
    (arg1 expand);
  run_set "condense.iscondensed" ~flags:["null", false] (getprop_raw_pub condenses "iscondensed")
    (arg1 (fun v -> Bool (iscondensed v)));
  run_condense_local ();

  (* minor *)
  run_set "minor.isnode" (mg "isnode") (arg1 (fun v -> Bool (isnode v)));
  run_set "minor.ismap" (mg "ismap") (arg1 (fun v -> Bool (ismap v)));
  run_set "minor.islist" (mg "islist") (arg1 (fun v -> Bool (islist v)));
  run_set "minor.iskey" ~flags:["null", false] (mg "iskey") (arg1 (fun v -> Bool (iskey v)));
  run_set "minor.strkey" ~flags:["null", false] (mg "strkey") (arg1 (fun v -> Str (strkey ~key:v ())));
  run_set "minor.isempty" ~flags:["null", false] (mg "isempty") (arg1 (fun v -> Bool (isempty v)));
  run_set "minor.isfunc" (mg "isfunc") (arg1 (fun v -> Bool (isfunc v)));
  run_set "minor.clone" ~flags:["null", false] (mg "clone") (arg1 clone);
  run_set "minor.escre" (mg "escre") (arg1 escre);
  run_set "minor.escurl" (mg "escurl") (arg1 escurl);
  run_set "minor.stringify" ~flags:["null", false] (mg "stringify")
    (arg1 (fun vin -> if vhas vin "val" then Str (stringify ~maxlen:(vget vin "max") (vget vin "val")) else Str (stringify Noval)));
  run_set "minor.jsonify" ~flags:["null", false] (mg "jsonify")
    (arg1 (fun vin -> Str (jsonify ~flags:(vget vin "flags") (vget vin "val"))));
  run_set "minor.getelem" ~flags:["null", false] (mg "getelem")
    (arg1 (fun vin -> let alt = vget vin "alt" in
            if is_nullish alt then getelem (vget vin "val") (vget vin "key")
            else getelem ~alt (vget vin "val") (vget vin "key")));
  run_set "minor.delprop" (mg "delprop")
    (arg1 (fun vin -> delprop (vget vin "parent") (vget vin "key")));
  run_set "minor.size" ~flags:["null", false] (mg "size") (arg1 (fun v -> vint (size v)));
  run_set "minor.slice" ~flags:["null", false] (mg "slice")
    (arg1 (fun vin -> slice ~start:(vget vin "start") ~stop:(vget vin "end") (vget vin "val")));
  run_set "minor.pad" ~flags:["null", false] (mg "pad")
    (arg1 (fun vin -> Str (pad ~padding:(vget vin "pad") ~padchar:(vget vin "char") (vget vin "val"))));
  run_set "minor.pathify" ~flags:["null", false] (mg "pathify")
    (arg1 (fun vin -> if vhas vin "path" then Str (pathify ~startin:(vget vin "from") (vget vin "path"))
            else Str (pathify ~startin:(vget vin "from") ~absent:true Noval)));
  run_set "minor.items" (mg "items") (arg1 items);
  (* Canonical omits `alt` only when the KEY is missing
     (`undefined === vin.alt`), so an explicit `alt: null` is passed through -
     unlike getelem, which omits a null alt too (`null == vin.alt`).
     `minor/getprop#51` is the entry that separates them. *)
  run_set "minor.getprop" ~flags:["null", false] (mg "getprop")
    (arg1 (fun vin ->
         if vhas vin "alt" then getprop ~alt:(vget vin "alt") (vget vin "val") (vget vin "key")
         else getprop (vget vin "val") (vget vin "key")));
  run_set "minor.setprop" (mg "setprop")
    (arg1 (fun vin -> setprop (vget vin "parent") (vget vin "key") (vget vin "val")));
  run_set "minor.haskey" ~flags:["null", false] (mg "haskey")
    (arg1 (fun vin -> Bool (haskey (vget vin "src") (vget vin "key"))));
  run_set "minor.keysof" (mg "keysof") (arg1 (fun v -> lst (List.map (fun s -> Str s) (keysof v))));
  run_set "minor.join" ~flags:["null", false] (mg "join")
    (arg1 (fun vin -> Str (join ~sep:(vget vin "sep") ~url:(match vget vin "url" with Bool true -> true | _ -> false) (vget vin "val"))));
  run_set "minor.typify" ~flags:["null", false] (mg "typify") (arg1 (fun v -> vint (typify v)));
  run_set "minor.setpath" ~flags:["null", false] (mg "setpath")
    (arg1 (fun vin -> setpath (vget vin "store") (vget vin "path") (vget vin "val")));
  run_set "minor.filter" (mg "filter")
    (arg1 (fun vin -> let check = (match vget vin "check" with
        | Str "gt3" -> (fun (_, x) -> match x with Num n -> n > 3.0 | _ -> false)
        | Str "lt3" -> (fun (_, x) -> match x with Num n -> n < 3.0 | _ -> false)
        | _ -> (fun _ -> false)) in
       filter (vget vin "val") check));
  run_set "minor.typename" (mg "typename") (arg1 (fun v -> Str (typename (match v with Num n -> int_of_float n | _ -> 0))));
  run_set "minor.flatten" (mg "flatten")
    (arg1 (fun vin -> flatten ?depth:(match vget vin "depth" with Num n -> Some (int_of_float n) | _ -> None) (vget vin "val")));

  (* walk *)
  run_walk_log "walk.log" (getprop_raw_pub walks "log");
  run_set "walk.basic" (getprop_raw_pub walks "basic")
    (arg1 (fun vin -> walk ~after:(fun _k v _p path ->
         match v with Str s -> Str (s ^ "~" ^ String.concat "." (List.map js_string (match path with List r -> !r | _ -> []))) | _ -> v) vin));
  run_set "walk.copy" (getprop_raw_pub walks "copy") (arg1 walk_copy_subject);
  run_set "walk.depth" ~flags:["null", false] (getprop_raw_pub walks "depth") (arg1 walk_depth_subject);

  (* merge *)
  run_single "merge.basic" (getprop_raw_pub merges "basic") (fun in_ -> merge (clone in_));
  run_set "merge.cases" (getprop_raw_pub merges "cases") (arg1 merge);
  run_set "merge.array" (getprop_raw_pub merges "array") (arg1 merge);
  run_set "merge.integrity" (getprop_raw_pub merges "integrity") (arg1 merge);
  run_set "merge.depth" (getprop_raw_pub merges "depth")
    (arg1 (fun vin -> merge ~maxdepth:(vget vin "depth") (vget vin "val")));

  (* getpath *)
  run_set "getpath.basic" (getprop_raw_pub getpaths "basic")
    (arg1 (fun vin -> getpath (vget vin "store") (vget vin "path")));
  run_set "getpath.relative" (getprop_raw_pub getpaths "relative")
    (arg1 (fun vin ->
         let dpath = (match vget vin "dpath" with Str s -> lst (List.map (fun x -> Str x) (String.split_on_char '.' s)) | _ -> Noval) in
         let d = { (default_injdef_pub ()) with d_dparent = vget vin "dparent"; d_dpath = dpath } in
         getpath ~inj:(IDef d) (vget vin "store") (vget vin "path")));
  run_set "getpath.special" (getprop_raw_pub getpaths "special")
    (arg1 (fun vin ->
         let injm = vget vin "inj" in
         let d = { (default_injdef_pub ()) with
                   d_base = getprop injm (Str "base"); d_meta = getprop injm (Str "meta");
                   d_dparent = getprop injm (Str "dparent"); d_dpath = getprop injm (Str "dpath");
                   d_key = getprop injm (Str "key") } in
         getpath ~inj:(if is_nullish injm then INone else IDef d) (vget vin "store") (vget vin "path")));
  run_set "getpath.handler" (getprop_raw_pub getpaths "handler")
    (arg1 (fun vin ->
         let store = omap_v ["$TOP", vget vin "store"; "$FOO", Func (fun _ _ _ _ -> Str "foo")] in
         let d = { (default_injdef_pub ()) with d_handler = Some (fun _inj v _ref _store -> match v with Func f -> f (Obj.magic 0) Noval "" Noval | _ -> v) } in
         getpath ~inj:(IDef d) store (vget vin "path")));

  (* inject *)
  run_single "inject.basic" (getprop_raw_pub injects "basic")
    (fun in_ -> inject (clone (getprop_raw_pub in_ "val")) (clone (getprop_raw_pub in_ "store")));
  run_set "inject.string" (getprop_raw_pub injects "string")
    (arg1 (fun vin ->
         let d = { (default_injdef_pub ()) with d_modify = Some null_modifier; d_extra = vget vin "current" } in
         inject ~inj:(IDef d) (vget vin "val") (vget vin "store")));
  run_set "inject.deep" (getprop_raw_pub injects "deep")
    (arg1 (fun vin -> inject (vget vin "val") (vget vin "store")));

  (* transform *)
  run_single "transform.basic" (getprop_raw_pub transforms "basic")
    (fun in_ -> transform (getprop_raw_pub in_ "data") (getprop_raw_pub in_ "spec"));
  List.iter (fun gn ->
      run_set ("transform." ^ gn) (getprop_raw_pub transforms gn)
        (arg1 (fun vin -> transform (vget vin "data") (vget vin "spec"))))
    ["paths"; "cmds"; "each"; "pack"; "ref"];
  run_set "transform.modify" (getprop_raw_pub transforms "modify")
    (arg1 (fun vin ->
         let d = { (default_injdef_pub ()) with
                   d_modify = Some (fun v key parent _inj ->
                       (match v with Str s when not (is_nullish key) && not (is_nullish parent) -> ignore (setprop parent key (Str ("@" ^ s))) | _ -> ()));
                   d_extra = vget vin "store" } in
         transform ~inj:(IDef d) (vget vin "data") (vget vin "spec")));
  run_set "transform.format" ~flags:["null", false] (getprop_raw_pub transforms "format")
    (arg1 (fun vin -> transform (vget vin "data") (vget vin "spec")));
  run_set "transform.apply" (getprop_raw_pub transforms "apply")
    (arg1 (fun vin -> transform (vget vin "data") (vget vin "spec")));

  (* validate *)
  run_set "validate.basic" ~flags:["null", false] (getprop_raw_pub validates "basic")
    (arg1 (fun vin -> validate (vget vin "data") (vget vin "spec")));
  List.iter (fun gn ->
      run_set ("validate." ^ gn) (getprop_raw_pub validates gn)
        (arg1 (fun vin -> validate (vget vin "data") (vget vin "spec"))))
    ["child"; "exact"];
  List.iter (fun gn ->
      run_set ("validate." ^ gn) ~flags:["null", false] (getprop_raw_pub validates gn)
        (arg1 (fun vin -> validate (vget vin "data") (vget vin "spec"))))
    ["invalid"; "directive"; "nof"; "all"; "len"; "range"; "like"; "unknown"];
  run_set "validate.special" (getprop_raw_pub validates "special")
    (arg1 (fun vin ->
         let injm = vget vin "inj" in
         let d = { (default_injdef_pub ()) with d_meta = getprop injm (Str "meta") } in
         validate ~inj:(if is_nullish injm then INone else IDef d) (vget vin "data") (vget vin "spec")));
  (* The corpus pins the message; this counts the errs, root forms included. *)
  run_local "validate.child-one-error-per-failure" (fun () ->
      List.iter (fun (dat, sp) ->
          let errs = empty_list () in
          ignore (validate ~inj:(IDef { (default_injdef_pub ()) with d_errs = errs }) dat sp);
          expect (size errs = 1) (compact errs))
        [jm [Str "x"; Num 1.0], jm [Str "x"; jm [Str "`$CHILD`"; Str "`$NUMBER`"]];
         jm [Str "x"; Num 1.0], jm [Str "x"; jt [Str "`$CHILD`"; Str "`$NUMBER`"]];
         Num 1.0, jm [Str "`$CHILD`"; Str "`$NUMBER`"];
         Num 1.0, jt [Str "`$CHILD`"; Str "`$NUMBER`"]]);

  (* select *)
  List.iter (fun gn ->
      run_set ("select." ^ gn) (getprop_raw_pub selects gn)
        (arg1 (fun vin -> select (vget vin "obj") (vget vin "query"))))
    ["basic"; "operators"; "edge"; "alts"];
  (* `null: false` keeps a JSON null an ACTUAL null rather than the NULLMARK
     string, so select sees a present-but-null field. *)
  run_set "select.nullkey" ~flags:["null", false] (getprop_raw_pub selects "nullkey")
    (arg1 (fun vin -> select (vget vin "obj") (vget vin "query")));

  (* regex (parity floor: Go stdlib regexp — see design/REGEX_API.md) *)
  let regexs = g "regex" in
  run_set "regex.test" (getprop_raw_pub regexs "test")
    (arg1 (fun vin -> re_test (vget vin "pattern") (vget vin "input")));
  run_set "regex.find" (getprop_raw_pub regexs "find")
    (arg1 (fun vin -> re_find (vget vin "pattern") (vget vin "input")));
  run_set "regex.find_all" (getprop_raw_pub regexs "find_all")
    (arg1 (fun vin -> re_find_all (vget vin "pattern") (vget vin "input")));
  run_set "regex.replace" (getprop_raw_pub regexs "replace")
    (arg1 (fun vin -> re_replace (vget vin "pattern") (vget vin "input") (vget vin "replacement")));
  run_set "regex.escape" (getprop_raw_pub regexs "escape")
    (arg1 (fun vin -> re_escape (vget vin "val")));

  (* sentinels *)
  run_set "sentinels.getprop_unify" ~flags:["null", false] (getprop_raw_pub sentinels "getprop_unify")
    (arg1 (fun vin -> getprop ~alt:(vget vin "alt") (vget vin "val") (vget vin "key")));
  run_set "sentinels.getelem_absent" ~flags:["null", false] (getprop_raw_pub sentinels "getelem_absent")
    (arg1 (fun vin -> getelem ~alt:(vget vin "alt") (vget vin "val") (vget vin "key")));
  run_set "sentinels.haskey_unify" ~flags:["null", false] (getprop_raw_pub sentinels "haskey_unify")
    (arg1 (fun vin -> Bool (haskey (vget vin "val") (vget vin "key"))));
  run_set "sentinels.isempty_unify" ~flags:["null", false] (getprop_raw_pub sentinels "isempty_unify")
    (arg1 (fun v -> Bool (isempty v)));
  run_set "sentinels.isnode_unify" ~flags:["null", false] (getprop_raw_pub sentinels "isnode_unify")
    (arg1 (fun v -> Bool (isnode v)));
  run_set "sentinels.stringify_null" ~flags:["null", false] (getprop_raw_pub sentinels "stringify_null")
    (arg1 (fun vin -> Str (stringify vin)))

and run_walk_log group node =
  try
    let test_data = clone node in
    let log = empty_list () in
    let walklog key v parent path =
      ignore (setprop log (Num (float_of_int (size log)))
                (Str (Printf.sprintf "k=%s, v=%s, p=%s, t=%s"
                        (if is_nullish key then stringify Noval else stringify key)
                        (stringify v)
                        (if is_nullish parent then stringify Noval else stringify parent)
                        (pathify path))));
      v in
    ignore (walk ~after:walklog (getprop_raw_pub test_data "in"));
    let expected = getprop (getprop_raw_pub test_data "out") (Str "after") in
    if eqv expected log then record (group ^ ".log") true ""
    else record (group ^ ".log") false (Printf.sprintf "Expected: %s, got: %s" (stringify expected) (stringify log))
  with e -> record (group ^ ".log") false (match e with Struct_error m -> m | _ -> Printexc.to_string e)

and walk_copy_subject vin =
  let cur = ref (lst [Noval]) in
  let walkcopy key v _parent path =
    if is_nullish key then begin
      cur := lst [(if ismap v then empty_map () else if islist v then empty_list () else v)];
      v
    end else begin
      let i = size path in
      let nv = if isnode v then begin
          (match !cur with List r -> while List.length !r <= i do r := !r @ [Noval] done | _ -> ());
          let n = if ismap v then empty_map () else empty_list () in
          (match !cur with List r -> r := List.mapi (fun j x -> if j = i then n else x) !r | _ -> ());
          n
        end else v in
      ignore (setprop (getelem !cur (Num (float_of_int (i - 1)))) key nv);
      v
    end in
  ignore (walk ~before:walkcopy vin);
  getelem !cur (Num 0.0)

and walk_depth_subject vin =
  let top = ref Noval and curr = ref Noval in
  let copy key v _parent _path =
    (if is_nullish key || isnode v then begin
        let child = if islist v then empty_list () else empty_map () in
        if is_nullish key then (top := child; curr := child)
        else (ignore (setprop !curr key child); curr := child)
      end else ignore (setprop !curr key v));
    v in
  ignore (walk ~before:copy ~maxdepth:(vget vin "maxdepth") (vget vin "src"));
  !top


(* ---------------- the client path ---------------- *)

(* `DEF.client`, client-scoped options, and `contextify`. This port had no such
   test. It is the only thing that exercises subject resolution through a
   PROVIDER rather than through a callback this file hands over - so nothing
   here had ever checked that a corpus `client` key resolves, or that a
   `DEF.client` entry's options reach the subject.

   The subject talks to omni DIRECTLY, in omni's own value type: the runner
   resolves it by name off the provider, so there is no `in` to convert and no
   result for the bridge to convert back. *)
let check options args =
  let foo = O.jget options "foo" in
  let foos = if O.isabsent foo then "" else O.stringify foo in
  let ctx = match args with first :: _ -> first | [] -> O.Absent in
  let bar = O.jget (O.jget ctx "meta") "bar" in
  let bars = if O.isnone bar then "0" else O.stringify bar in
  O.JMap [ ("zed", O.Str ("ZED" ^ foos ^ "_" ^ bars)) ]

let rec client_provider options =
  (* Built FROM `empty_provider`, not as a bare literal: omni's provider
     record is a shared type that gains optional hooks over time, and every
     bare literal here breaks the moment it does -- `errify` was the one that
     did it. `with` names only the hooks this port implements and takes the
     None default for the rest. Line 427 below already reads it this way. *)
  {
    O.empty_provider with
    O.subject = Some (fun name -> if name = "check" then Some (check options) else None);
    (* A DEF.client entry becomes another provider, carrying its options. *)
    O.client = Some client_provider;
    (* This port adds nothing to a context; the hook must exist so omni
       installs `client` on it. *)
    O.contextify = Some (fun value -> value);
  }

let run_client testfile =
  let resolved = O.make_runner testfile (client_provider (O.JMap [])) "check" None in
  let useflags = { O.null = true; name = Some "check.basic" } in
  (* No subject: the runner resolves it by name off the provider, which is the
     whole point of the group. *)
  match resolved.O.runsetflags (resolved.O.set "basic") useflags None with
  | () -> record "check.basic" true ""
  | exception O.Omni_error message -> record "check.basic" false message
  | exception err -> record "check.basic" false (Printexc.to_string err)

(* ---------------- main ---------------- *)

let () =
  (* omni reads an error it does not know through Printexc; an `err` pattern
     anchored at both ends needs the bare message. *)
  Printexc.register_printer (function Struct_error message -> Some message | _ -> None);
  let testfile = if Array.length Sys.argv > 1 then Sys.argv.(1) else "../build/test/test.json" in
  let resolved = O.make_runner testfile O.empty_provider "struct" None in
  runpack := Some resolved;
  run_all (tostruct resolved.O.spec);
  run_client testfile;
  List.iter print_endline (List.rev !failures);
  Printf.printf "\n%d groups, %d failed\n" (!npass + !nfail) !nfail;
  if !nfail > 0 then exit 1
