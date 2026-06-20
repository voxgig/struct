(* Test runner for the shared JSON corpus (build/test/test.json).
 * Self-contained: an in-tree JSON reader builds the library's `value` type
 * directly, so the OCaml port is exercised exactly as in production. *)

open Voxgig_struct

let nullmark = "__NULL__"
let undefmark = "__UNDEF__"
let existsmark = "__EXISTS__"

(* ---------------- JSON reader -> value ---------------- *)

let json_read (s : string) : value =
  let n = String.length s in
  let pos = ref 0 in
  let peek () = if !pos < n then Some s.[!pos] else None in
  let adv () = incr pos in
  let skip_ws () =
    while !pos < n && (match s.[!pos] with ' ' | '\t' | '\n' | '\r' -> true | _ -> false) do incr pos done
  in
  let rec pval () =
    skip_ws ();
    match peek () with
    | Some '{' -> pobj ()
    | Some '[' -> parr ()
    | Some '"' -> Str (pstr ())
    | Some 't' -> pos := !pos + 4; Bool true
    | Some 'f' -> pos := !pos + 5; Bool false
    | Some 'n' -> pos := !pos + 4; Null
    | _ -> pnum ()
  and pobj () =
    adv (); skip_ws ();
    if peek () = Some '}' then (adv (); empty_map ())
    else begin
      let m = empty_map () in
      let rec loop () =
        skip_ws ();
        let k = pstr () in
        skip_ws (); adv (); (* : *)
        let v = pval () in
        ignore (setprop m (Str k) v);
        skip_ws ();
        let c = (match peek () with Some c -> adv (); c | None -> '}') in
        if c = ',' then loop () else m
      in loop ()
    end
  and parr () =
    adv (); skip_ws ();
    if peek () = Some ']' then (adv (); empty_list ())
    else begin
      let acc = ref [] in
      let rec loop () =
        let v = pval () in
        acc := v :: !acc;
        skip_ws ();
        let c = (match peek () with Some c -> adv (); c | None -> ']') in
        if c = ',' then loop () else lst (List.rev !acc)
      in loop ()
    end
  and pstr () =
    adv ();
    let b = Buffer.create 16 in
    let rec loop () =
      let c = s.[!pos] in adv ();
      if c = '"' then Buffer.contents b
      else if c = '\\' then begin
        let e = s.[!pos] in adv ();
        (match e with
         | '"' -> Buffer.add_char b '"' | '\\' -> Buffer.add_char b '\\'
         | '/' -> Buffer.add_char b '/' | 'n' -> Buffer.add_char b '\n'
         | 't' -> Buffer.add_char b '\t' | 'r' -> Buffer.add_char b '\r'
         | 'b' -> Buffer.add_char b '\b' | 'f' -> Buffer.add_char b '\012'
         | 'u' ->
           let hex = String.sub s !pos 4 in pos := !pos + 4;
           let code = int_of_string ("0x" ^ hex) in
           if code < 128 then Buffer.add_char b (Char.chr code)
           else if code < 2048 then begin
             Buffer.add_char b (Char.chr (0xC0 lor (code lsr 6)));
             Buffer.add_char b (Char.chr (0x80 lor (code land 0x3F)))
           end else begin
             Buffer.add_char b (Char.chr (0xE0 lor (code lsr 12)));
             Buffer.add_char b (Char.chr (0x80 lor ((code lsr 6) land 0x3F)));
             Buffer.add_char b (Char.chr (0x80 lor (code land 0x3F)))
           end
         | c -> Buffer.add_char b c);
        loop ()
      end else (Buffer.add_char b c; loop ())
    in loop ()
  and pnum () =
    let start = !pos in
    while !pos < n && (match s.[!pos] with
        | '0'..'9' | '-' | '+' | '.' | 'e' | 'E' -> true | _ -> false) do incr pos done;
    let tok = String.sub s start (!pos - start) in
    Num (float_of_string tok)
  in
  pval ()

(* ---------------- fixJSON / equality ---------------- *)

let rec fix_json v flag_null =
  match v with
  | Noval | Null -> if flag_null then Str nullmark else v
  | Map m -> let o = empty_map () in
    List.iter (fun (k, x) -> ignore (setprop o (Str k) (fix_json x flag_null))) m.entries; o
  | List r -> lst (List.map (fun x -> fix_json x flag_null) !r)
  | _ -> v

(* Order-independent deep equality for maps; sequence equality for lists. *)
let rec eqv a b =
  match a, b with
  | (Noval | Null), (Noval | Null) -> true
  | Bool x, Bool y -> x = y
  | Num x, Num y -> x = y
  | Str x, Str y -> x = y
  | List x, List y -> List.length !x = List.length !y && List.for_all2 eqv !x !y
  | Map x, Map y ->
    omap_len x = omap_len y &&
    List.for_all (fun (k, v) -> match omap_get y k with Some w -> eqv v w | None -> false) x.entries
  | _ -> a == b

(* ---------------- match support ---------------- *)

let matchval check base =
  let check = if check = Str undefmark || check = Str nullmark then Noval else check in
  if eqv check base then true
  else match check with
    | Str cs ->
      let basestr = stringify base in
      if String.length cs >= 2 && cs.[0] = '/' && cs.[String.length cs - 1] = '/' then
        Vregex.test_str (String.sub cs 1 (String.length cs - 2)) basestr
      else
        let low s = String.lowercase_ascii s in
        let contains hay needle =
          let hl = String.length hay and nl = String.length needle in
          let rec go i = if i + nl > hl then false
            else if String.sub hay i nl = needle then true else go (i + 1) in
          nl = 0 || go 0 in
        contains (low basestr) (low (stringify check))
    | Func _ -> true
    | _ -> false

let do_match check base =
  let base = clone base in
  ignore (walk ~before:(fun _k v _p path ->
      (if not (isnode v) then begin
          let baseval = getpath base path in
          if eqv baseval v then ()
          else if v = Str undefmark && is_nullish baseval then ()
          else if v = Str existsmark && not (is_nullish baseval) then ()
          else if not (matchval v baseval) then
            raise (Struct_error (Printf.sprintf "MATCH: %s: [%s] <=> [%s]"
                                   (String.concat "." (List.map js_string (match path with List r -> !r | _ -> [])))
                                   (stringify v) (stringify baseval)))
        end);
      v) check)

(* ---------------- result tracking ---------------- *)

let npass = ref 0
let nfail = ref 0
let failures = ref []

let record group name ok msg =
  if ok then incr npass
  else (incr nfail; failures := Printf.sprintf "FAIL %s %s - %s" group name msg :: !failures)

(* ---------------- per-entry runner ---------------- *)

let omap_v kvs =
  let m = empty_map () in
  List.iter (fun (k, v) -> ignore (setprop m (Str k) v)) kvs; m

let getprop_raw_pub e k = (match e with Map m -> (match omap_get m k with Some x -> x | None -> Noval) | _ -> Noval)
let entry_get e k = getprop_raw_pub e k
let entry_has e k = match e with Map m -> omap_has m k | _ -> false
let default_injdef_pub () =
  { d_meta = Noval; d_extra = Noval; d_errs = Noval; d_modify = None; d_handler = None;
    d_base = Noval; d_dparent = Noval; d_dpath = Noval; d_key = Noval }

let resolve_args entry =
  if entry_has entry "ctx" then [entry_get entry "ctx"]
  else if entry_has entry "args" then (match entry_get entry "args" with List r -> !r | _ -> [])
  else if entry_has entry "in" then [clone (entry_get entry "in")]
  else [Noval]

let check_result entry args res =
  let matched = ref false in
  (if entry_has entry "match" then begin
      do_match (entry_get entry "match")
        (omap_v ["in", entry_get entry "in"; "args", lst args;
                 "out", entry_get entry "res"; "ctx", entry_get entry "ctx"]);
      matched := true
    end);
  let out = entry_get entry "out" in
  if eqv out res then ()
  else if !matched && (out = Str nullmark || is_nullish out) then ()
  else raise (Struct_error (Printf.sprintf "Expected: %s, got: %s" (stringify out) (stringify res)))

let handle_error entry err =
  let msg = (match err with Struct_error m -> m | e -> Printexc.to_string e) in
  if entry_has entry "err" then begin
    let entry_err = entry_get entry "err" in
    if entry_err = Bool true || matchval entry_err (Str msg) then begin
      if entry_has entry "match" then
        do_match (entry_get entry "match")
          (omap_v ["in", entry_get entry "in"; "out", entry_get entry "res";
                   "ctx", entry_get entry "ctx"; "err", Str msg])
    end else
      raise (Struct_error (Printf.sprintf "ERROR MATCH: [%s] <=> [%s]" (stringify entry_err) msg))
  end else raise err

let run_set ?(flags = []) group node subject =
  let flag_null = (match List.assoc_opt "null" flags with Some b -> b | None -> true) in
  let fixed = fix_json node flag_null in
  let testset = (match getprop fixed (Str "set") with List r -> !r | _ -> []) in
  List.iter (fun entry ->
      let name = js_string (entry_get entry "name") in
      try
        (if not (entry_has entry "out") && flag_null then ignore (setprop entry (Str "out") (Str nullmark)));
        let args = resolve_args entry in
        let res = fix_json (subject args) flag_null in
        ignore (setprop entry (Str "res") res);
        check_result entry args res;
        record group name true ""
      with
      | e ->
        (try handle_error entry e; record group name true ""
         with e2 -> record group name false
                      (match e2 with Struct_error m -> m | _ -> Printexc.to_string e2)))
    testset

let run_single group node actual_fn =
  try
    let expected = getprop_raw_pub node "out" in
    let actual = actual_fn (getprop_raw_pub node "in") in
    if eqv expected actual then record group "single" true ""
    else record group "single" false (Printf.sprintf "Expected: %s, got: %s" (stringify expected) (stringify actual))
  with e -> record group "single" false (match e with Struct_error m -> m | _ -> Printexc.to_string e)

(* ---------------- arg helpers ---------------- *)

let arg1 f = fun args -> f (match args with x :: _ -> x | [] -> Noval)
let vget vin k = match vin with Map m -> (match omap_get m k with Some x -> x | None -> Noval) | _ -> Noval
let vhas vin k = match vin with Map m -> omap_has m k | _ -> false

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

let rec run_all spec =
  let g k = getprop_raw_pub spec k in
  ignore g;
  let minor = g "minor" and walks = g "walk" and merges = g "merge"
  and getpaths = g "getpath" and injects = g "inject" and transforms = g "transform"
  and validates = g "validate" and selects = g "select" and sentinels = g "sentinels" in
  let mg n = getprop_raw_pub minor n in

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
  run_set "minor.getprop" ~flags:["null", false] (mg "getprop")
    (arg1 (fun vin -> let alt = vget vin "alt" in
            if is_nullish alt then getprop (vget vin "val") (vget vin "key")
            else getprop ~alt (vget vin "val") (vget vin "key")));
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
    ["child"; "one"; "exact"];
  run_set "validate.invalid" ~flags:["null", false] (getprop_raw_pub validates "invalid")
    (arg1 (fun vin -> validate (vget vin "data") (vget vin "spec")));
  run_set "validate.special" (getprop_raw_pub validates "special")
    (arg1 (fun vin ->
         let injm = vget vin "inj" in
         let d = { (default_injdef_pub ()) with d_meta = getprop injm (Str "meta") } in
         validate ~inj:(if is_nullish injm then INone else IDef d) (vget vin "data") (vget vin "spec")));

  (* select *)
  List.iter (fun gn ->
      run_set ("select." ^ gn) (getprop_raw_pub selects gn)
        (arg1 (fun vin -> select (vget vin "obj") (vget vin "query"))))
    ["basic"; "operators"; "edge"; "alts"];

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
    if eqv expected log then record group "log" true ""
    else record group "log" false (Printf.sprintf "Expected: %s, got: %s" (stringify expected) (stringify log))
  with e -> record group "log" false (match e with Struct_error m -> m | _ -> Printexc.to_string e)

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

(* ---------------- main ---------------- *)

let () =
  let testfile = if Array.length Sys.argv > 1 then Sys.argv.(1) else "../build/test/test.json" in
  let ic = open_in_bin testfile in
  let len = in_channel_length ic in
  let raw = really_input_string ic len in
  close_in ic;
  let alltests = json_read raw in
  let spec = getprop_raw_pub alltests "struct" in
  run_all spec;
  List.iter print_endline (List.rev !failures);
  Printf.printf "\nPASS %d  FAIL %d\n" !npass !nfail;
  if !nfail > 0 then exit 1
