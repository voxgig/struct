(* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
 *
 * Voxgig Struct — OCaml port.
 *
 * A faithful port of the canonical TypeScript implementation
 * (typescript/src/StructUtility.ts). Like TypeScript (and the Rust port),
 * OCaml keeps `undefined` (Noval) and JSON `null` (Null) distinct, so this
 * port mirrors the canonical TS logic directly. Nodes are mutable and
 * reference-stable: lists are `value list ref`, maps are an in-tree ordered
 * map (insertion order preserved). Zero third-party runtime dependencies; the
 * regex helper is the in-tree Vregex engine (RE2 subset). *)

(* ---------------------------------------------------------------------------
 * Value model
 * ------------------------------------------------------------------------- *)

type value =
  | Noval                          (* TS undefined — property absent *)
  | Null                           (* JSON null *)
  | Bool of bool
  | Num of float
  | Str of string
  | List of value list ref
  | Map of omap
  | Func of injector
  | Sentinel of string             (* SKIP / DELETE, by tag *)

and omap = { mutable entries : (string * value) list }

and injector = inj -> value -> string -> value -> value

and modifyfn = value -> value -> value -> inj -> unit

and inj = {
  mutable mode : int;
  mutable full : bool;
  mutable keyi : int;
  mutable keys : value;            (* List of Str *)
  mutable key : value;             (* Str *)
  mutable ival : value;
  mutable parent : value;
  mutable path : value;            (* List of Str *)
  mutable nodes : value;           (* List *)
  mutable handler : injector;
  mutable errs : value;            (* List *)
  mutable meta : value;            (* Map *)
  mutable dparent : value;
  mutable dpath : value;           (* List *)
  mutable base : value;            (* Str or Noval *)
  mutable modify : modifyfn option;
  mutable prior : inj option;
  mutable extra : value;
}

(* injdef: the loose Partial<Injection> the public API accepts. *)
and injdef = {
  mutable d_meta : value;
  mutable d_extra : value;
  mutable d_errs : value;
  mutable d_modify : modifyfn option;
  mutable d_handler : injector option;
  mutable d_base : value;
  mutable d_dparent : value;
  mutable d_dpath : value;
  mutable d_key : value;
}

type injarg = IInj of inj | IDef of injdef | INone

exception Struct_error of string

(* ---------------------------------------------------------------------------
 * Constants
 * ------------------------------------------------------------------------- *)

let m_keypre = 1
let m_keypost = 2
let m_val = 4

let s_dkey = "$KEY"
let s_banno = "`$ANNO`"
let s_dtop = "$TOP"
let s_derrs = "$ERRS"
let s_dspec = "$SPEC"
let s_bexact = "`$EXACT`"
let s_bval = "`$VAL`"
let s_bkey = "`$KEY`"
let s_bopen = "`$OPEN`"

let s_mt = ""
let s_bt = "`"
let s_ds = "$"
let s_dt = "."
let s_cn = ":"
let s_fs = "/"
let s_key = "KEY"
let s_viz = ": "

let s_string = "string"
let s_object = "object"
let s_list = "list"
let s_map = "map"
let s_nil = "nil"
let s_null = "null"

let t_any = (1 lsl 31) - 1
let t_noval = 1 lsl 30
let t_boolean = 1 lsl 29
let t_decimal = 1 lsl 28
let t_integer = 1 lsl 27
let t_number = 1 lsl 26
let t_string = 1 lsl 25
let t_function = 1 lsl 24
let t_null = 1 lsl 22
let t_list = 1 lsl 14
let t_map = 1 lsl 13
let t_instance = 1 lsl 12
let t_scalar = 1 lsl 7
let t_node = 1 lsl 6

let typename_tbl = [|
  "any"; "nil"; "boolean"; "decimal"; "integer"; "number"; "string"; "function";
  "symbol"; "null"; ""; ""; ""; ""; ""; ""; ""; "list"; "map"; "instance";
  ""; ""; ""; ""; "scalar"; "node" |]

let skip = Sentinel "skip"
let delete = Sentinel "delete"

let maxdepth = 32

(* ---------------------------------------------------------------------------
 * Small helpers
 * ------------------------------------------------------------------------- *)

let lst l = List (ref l)
let empty_list () = List (ref [])
let empty_map () = Map { entries = [] }
let vstr s = Str s
let vint i = Num (float_of_int i)

let is_noval = function Noval -> true | _ -> false
let is_nullish = function Noval | Null -> true | _ -> false
let is_skip v = (match v with Sentinel "skip" -> true | _ -> false)
let is_delete v = (match v with Sentinel "delete" -> true | _ -> false)

let is_integer_f n = Float.is_finite n && Float.rem n 1.0 = 0.0

let num_to_string n =
  if Float.is_nan n then "NaN"
  else if Float.is_integer n && Float.abs n < 1e16 then Printf.sprintf "%.0f" n
  else begin
    let rec try_prec p =
      if p > 17 then Printf.sprintf "%.17g" n
      else let s = Printf.sprintf "%.*g" p n in
        if float_of_string s = n then s else try_prec (p + 1)
    in try_prec 1
  end

(* JS `'' + v` / String(v) for keys and concatenation. *)
let rec js_string v =
  match v with
  | Noval -> "undefined"
  | Null -> "null"
  | Bool b -> if b then "true" else "false"
  | Num n -> num_to_string n
  | Str s -> s
  | List r ->
    String.concat ","
      (List.map (fun x -> match x with Noval | Null -> "" | _ -> js_string x) !r)
  | Map _ -> "[object Object]"
  | Func _ -> "function"
  | Sentinel s -> s

let is_int_key s =
  let n = String.length s in
  n > 0 &&
  (let ok = ref true in
   String.iteri (fun i c ->
       if not ((c >= '0' && c <= '9') || (c = '-')) then ok := false;
       ignore i) s;
   !ok)

let clz32 n =
  let n = n land 0xFFFFFFFF in
  if n = 0 then 32
  else begin
    let r = ref 0 and x = ref n in
    while !x land 0x80000000 = 0 do incr r; x := (!x lsl 1) land 0xFFFFFFFF done;
    !r
  end

(* ----- ordered map ops ----- *)
let omap_get m k = try Some (List.assoc k m.entries) with Not_found -> None
let omap_has m k = List.mem_assoc k m.entries
let omap_keys m = List.map fst m.entries
let omap_len m = List.length m.entries
let omap_set m k v =
  if List.mem_assoc k m.entries then
    m.entries <- List.map (fun (k', v') -> if k' = k then (k, v) else (k', v')) m.entries
  else m.entries <- m.entries @ [(k, v)]
let omap_del m k = m.entries <- List.filter (fun (k', _) -> k' <> k) m.entries

(* ---------------------------------------------------------------------------
 * The big mutually-recursive block of library functions
 * ------------------------------------------------------------------------- *)

(* a placeholder inj for the (corpus-unreached) getelem function-alt path *)
let dummy_inj_ref : inj option ref = ref None

let rec isnode v = match v with Map _ | List _ -> true | _ -> false
and ismap v = match v with Map _ -> true | _ -> false
and islist v = match v with List _ -> true | _ -> false
and isfunc v = match v with Func _ -> true | _ -> false

and iskey k = match k with Str s -> s <> "" | Num _ -> true | _ -> false

and isempty v =
  is_nullish v || v = Str "" ||
  (match v with List r -> !r = [] | Map m -> m.entries = [] | _ -> false)

and getdef v alt = if is_noval v then alt else v

and typify v =
  match v with
  | Noval -> t_noval
  | Null -> t_scalar lor t_null
  | Bool _ -> t_scalar lor t_boolean
  | Num n ->
    if Float.is_nan n then t_noval
    else if is_integer_f n then t_scalar lor t_number lor t_integer
    else t_scalar lor t_number lor t_decimal
  | Str _ -> t_scalar lor t_string
  | Func _ -> t_scalar lor t_function
  | List _ -> t_node lor t_list
  | Map _ -> t_node lor t_map
  | Sentinel _ -> t_node lor t_map

and typename t =
  let i = clz32 t in
  if i >= 0 && i < Array.length typename_tbl then typename_tbl.(i) else typename_tbl.(0)

and size v =
  match v with
  | List r -> List.length !r
  | Map m -> omap_len m
  | Str s -> String.length s
  | Bool b -> if b then 1 else 0
  | Num n -> int_of_float (Float.floor n)
  | _ -> 0

and strkey ?(key = Noval) () =
  match key with
  | Noval -> s_mt
  | Str s -> s
  | Bool _ -> s_mt
  | Num n -> if is_integer_f n then num_to_string n else num_to_string (Float.floor n)
  | _ -> s_mt

and keysof v =
  match v with
  | Map m -> List.sort compare (omap_keys m)
  | List r -> List.mapi (fun i _ -> string_of_int i) !r
  | _ -> []

(* internal: list element by numeric key, no negative wrap, returns Noval if oob *)
and list_index lr key =
  let ks = (match key with Str s -> s | Num n -> num_to_string n | _ -> "") in
  match int_of_string_opt ks with
  | Some i when i >= 0 && i < List.length !lr -> List.nth !lr i
  | _ -> Noval

and getprop ?(alt = Noval) v key =
  if is_noval v || is_noval key then alt
  else
    let out =
      match v with
      | Map m -> (match omap_get m (js_string key) with Some x -> x | None -> Noval)
      | List r -> list_index r key
      | _ -> Noval
    in
    if is_nullish out then alt else out

and lookup_ v key =
  if is_noval v || is_noval key then Noval
  else match v with
    | Map m -> (match omap_get m (js_string key) with Some x -> x | None -> Noval)
    | List r -> list_index r key
    | _ -> Noval

and haskey v key = not (is_nullish (getprop v key))

and getelem ?(alt = Noval) v key =
  if is_noval v || is_noval key then alt
  else begin
    let out = ref Noval in
    (match v with
     | List r ->
       let ks = (match key with Str s -> s | Num n -> num_to_string n | _ -> "") in
       if is_int_key ks then begin
         let len = List.length !r in
         let nk0 = int_of_string ks in
         let nk = if nk0 < 0 then len + nk0 else nk0 in
         if nk >= 0 && nk < len then out := List.nth !r nk
       end
     | _ -> ());
    if is_nullish !out then
      (match alt with
       | Func f -> f (Option.get !dummy_inj_ref) Noval "" Noval
       | _ -> alt)
    else !out
  end

and items_pairs v : (string * value) list =
  if not (isnode v) then []
  else List.map (fun k -> (k, getprop_raw v k)) (keysof v)

and getprop_raw v k =
  (* literal stored value at sorted-key k (string), preserving null *)
  match v with
  | Map m -> (match omap_get m k with Some x -> x | None -> Noval)
  | List r -> (try List.nth !r (int_of_string k) with _ -> Noval)
  | _ -> Noval

and items_v v (f : (string * value) -> value) : value =
  lst (List.map f (items_pairs v))

and items v : value =
  lst (List.map (fun (k, x) -> lst [Str k; x]) (items_pairs v))

and flatten ?(depth = 1) l =
  if not (islist l) then l
  else begin
    let out = ref [] in
    (match l with List r ->
      List.iter (fun item ->
          if islist item && depth > 0 then
            (match flatten ~depth:(depth - 1) item with
             | List r2 -> List.iter (fun x -> out := x :: !out) !r2
             | _ -> ())
          else out := item :: !out) !r
     | _ -> ());
    lst (List.rev !out)
  end

and filter v check =
  let out = ref [] in
  List.iter (fun (k, x) -> if check (k, x) then out := x :: !out) (items_pairs v);
  lst (List.rev !out)

and setprop parent key v =
  if not (iskey key) then parent
  else begin
    (match parent with
     | Map m -> omap_set m (js_string key) v
     | List r ->
       let ks = (match key with Str s -> s | Num n -> num_to_string (Float.floor n) | _ -> "") in
       (match int_of_string_opt ks with
        | None -> ()
        | Some ki ->
          let len = List.length !r in
          if ki >= 0 then begin
            let ki = if ki > len then len else ki in
            if ki >= len then r := !r @ [v]
            else r := List.mapi (fun i x -> if i = ki then v else x) !r
          end else r := v :: !r)
     | _ -> ());
    parent
  end

and delprop parent key =
  if not (iskey key) then parent
  else begin
    (match parent with
     | Map m -> omap_del m (js_string key)
     | List r ->
       let ks = (match key with Str s -> s | Num n -> num_to_string (Float.floor n) | _ -> "") in
       (match int_of_string_opt ks with
        | Some ki when ki >= 0 && ki < List.length !r ->
          r := List.filteri (fun i _ -> i <> ki) !r
        | _ -> ())
     | _ -> ());
    parent
  end

and clone v =
  match v with
  | List r -> List (ref (List.map clone !r))
  | Map m -> Map { entries = List.map (fun (k, x) -> (k, clone x)) m.entries }
  | _ -> v

and slice ?(start = Noval) ?(stop = Noval) ?(mutate = false) v =
  match v with
  | Num n ->
    let lo = (match start with Num s -> s | _ -> neg_infinity) in
    let hi = (match stop with Num e -> e -. 1.0 | _ -> infinity) in
    Num (Float.max lo (Float.min n hi))
  | List _ | Str _ ->
    let vlen = size v in
    let start = (match start, stop with Noval, x when not (is_noval x) -> Num 0.0 | _ -> start) in
    (match start with
     | Num sf ->
       let s = int_of_float sf in
       let s, e =
         if s < 0 then 0, (let e = vlen + s in if e < 0 then 0 else e)
         else match stop with
           | Num ef ->
             let e = int_of_float ef in
             if e < 0 then s, (let e = vlen + e in if e < 0 then 0 else e)
             else if vlen < e then s, vlen
             else s, e
           | _ -> s, vlen
       in
       let s = if vlen < s then vlen else s in
       if s > -1 && s <= e && e <= vlen then
         (match v with
          | List r ->
            if mutate then begin
              r := (let arr = Array.of_list !r in Array.to_list (Array.sub arr s (e - s))); v
            end else lst (let arr = Array.of_list !r in Array.to_list (Array.sub arr s (e - s)))
          | Str str -> Str (String.sub str s (e - s))
          | _ -> v)
       else
         (match v with
          | List r -> if mutate then (r := []; v) else empty_list ()
          | Str _ -> Str s_mt
          | _ -> v)
     | _ -> v)
  | _ -> v

(* ----- regex helpers (uniform re_* API + targeted hand-rolled matchers) ----- *)

and re_compile ?flags:_ p = (match p with Str _ -> p | _ -> Str (js_string p))
and re_str p = (match p with Str s -> s | _ -> js_string p)
and re_find p input =
  (match Vregex.find_bounds (Vregex.compile (re_str p)) (re_str input) with
   | Some (s, e) -> lst [Str (String.sub (re_str input) s (e - s))]
   | None -> Null)
and re_find_all _p _input = empty_list ()
and re_replace _p input _r = input
and re_test p input = Bool (Vregex.test_str (re_str p) (re_str input))
and re_escape s = escre s

and escre s =
  let s = (match s with Str x -> x | Noval -> s_mt | _ -> js_string s) in
  let b = Buffer.create (String.length s) in
  String.iter (fun c ->
      (match c with
       | '.' | '*' | '+' | '?' | '^' | '$' | '{' | '}' | '(' | ')' | '|'
       | '[' | ']' | '\\' -> Buffer.add_char b '\\'
       | _ -> ());
      Buffer.add_char b c) s;
  Str (Buffer.contents b)

and escurl s =
  let s = (match s with Str x -> x | Noval -> s_mt | _ -> js_string s) in
  let b = Buffer.create (String.length s) in
  String.iter (fun c ->
      let unreserved =
        (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
        || c = '-' || c = '_' || c = '.' || c = '!' || c = '~' || c = '*'
        || c = '\'' || c = '(' || c = ')' in
      if unreserved then Buffer.add_char b c
      else Buffer.add_string b (Printf.sprintf "%%%02X" (Char.code c))) s;
  Str (Buffer.contents b)

(* ----- stringify / jsonify / pathify / join ----- *)

and json_encode ?(sort = false) ?indent v =
  let buf = Buffer.create 64 in
  let esc s =
    Buffer.add_char buf '"';
    String.iter (fun c ->
        match c with
        | '"' -> Buffer.add_string buf "\\\""
        | '\\' -> Buffer.add_string buf "\\\\"
        | '\n' -> Buffer.add_string buf "\\n"
        | '\r' -> Buffer.add_string buf "\\r"
        | '\t' -> Buffer.add_string buf "\\t"
        | c when Char.code c < 32 -> Buffer.add_string buf (Printf.sprintf "\\u%04x" (Char.code c))
        | c -> Buffer.add_char buf c) s;
    Buffer.add_char buf '"'
  in
  let rec enc v level =
    match v with
    | Noval | Null -> Buffer.add_string buf "null"
    | Bool b -> Buffer.add_string buf (if b then "true" else "false")
    | Num n -> Buffer.add_string buf (num_to_string n)
    | Str s -> esc s
    | Func _ | Sentinel _ -> Buffer.add_string buf "null"
    | List r ->
      if !r = [] then Buffer.add_string buf "[]"
      else (match indent with
          | Some ind ->
            let pad = String.make (ind * (level + 1)) ' ' in
            let cpad = String.make (ind * level) ' ' in
            Buffer.add_string buf "[\n";
            List.iteri (fun i x ->
                if i > 0 then Buffer.add_string buf ",\n";
                Buffer.add_string buf pad; enc x (level + 1)) !r;
            Buffer.add_string buf "\n"; Buffer.add_string buf cpad; Buffer.add_char buf ']'
          | None ->
            Buffer.add_char buf '[';
            List.iteri (fun i x -> if i > 0 then Buffer.add_char buf ','; enc x (level + 1)) !r;
            Buffer.add_char buf ']')
    | Map m ->
      let ks = List.map fst m.entries in
      let ks = if sort then List.sort compare ks else ks in
      if ks = [] then Buffer.add_string buf "{}"
      else (match indent with
          | Some ind ->
            let pad = String.make (ind * (level + 1)) ' ' in
            let cpad = String.make (ind * level) ' ' in
            Buffer.add_string buf "{\n";
            List.iteri (fun i k ->
                if i > 0 then Buffer.add_string buf ",\n";
                Buffer.add_string buf pad; esc k; Buffer.add_string buf ": ";
                enc (Option.get (omap_get m k)) (level + 1)) ks;
            Buffer.add_string buf "\n"; Buffer.add_string buf cpad; Buffer.add_char buf '}'
          | None ->
            Buffer.add_char buf '{';
            List.iteri (fun i k ->
                if i > 0 then Buffer.add_char buf ',';
                esc k; Buffer.add_char buf ':'; enc (Option.get (omap_get m k)) (level + 1)) ks;
            Buffer.add_char buf '}')
  in
  enc v 0; Buffer.contents buf

and has_cycle v =
  let seen = ref [] in
  let rec go v =
    match v with
    | List r -> if List.memq v !seen then true else (seen := v :: !seen; List.exists go !r)
    | Map m -> if List.memq v !seen then true else (seen := v :: !seen; List.exists (fun (_, x) -> go x) m.entries)
    | _ -> false
  in go v

and stringify ?(maxlen = Noval) ?(pretty = false) v =
  match v with
  | Noval -> if pretty then "<>" else s_mt
  | _ ->
    let valstr =
      match v with
      | Str s -> s
      | _ -> if has_cycle v then "__STRINGIFY_FAILED__"
        else (try let s = json_encode ~sort:true v in
                (* TS removes all double quotes *)
                String.concat "" (String.split_on_char '"' s)
              with _ -> "__STRINGIFY_FAILED__")
    in
    let valstr =
      match maxlen with
      | Num m when m > -1.0 ->
        let m = int_of_float m in
        let l = String.length valstr in
        if m < l then String.sub valstr 0 (max 0 (m - 3)) ^ "..."
        else valstr
      | _ -> valstr
    in
    if pretty then begin
      let colors = [81;118;213;39;208;201;45;190;129;51;160;121;226;33;207;69] in
      let c = Array.of_list (List.map (fun n -> Printf.sprintf "\027[38;5;%dm" n) colors) in
      let r = "\027[0m" in
      let d = ref 0 and o = ref c.(0) and t = Buffer.create 64 in
      Buffer.add_string t c.(0);
      String.iter (fun ch ->
          if ch = '{' || ch = '[' then begin
            incr d; o := c.(!d mod Array.length c);
            Buffer.add_string t !o; Buffer.add_char t ch
          end else if ch = '}' || ch = ']' then begin
            Buffer.add_string t !o; Buffer.add_char t ch;
            decr d; o := c.((((!d mod Array.length c) + Array.length c) mod Array.length c))
          end else (Buffer.add_string t !o; Buffer.add_char t ch)) valstr;
      Buffer.contents t ^ r
    end else valstr

and jsonify ?(flags = Noval) v =
  match v with
  | Noval -> s_null
  | _ ->
    let indent = (match getprop ~alt:(Num 2.0) flags (Str "indent") with Num n -> int_of_float n | _ -> 2) in
    (try
       let str = if indent > 0 then json_encode ~indent v else json_encode v in
       let offset = (match getprop ~alt:(Num 0.0) flags (Str "offset") with Num n -> int_of_float n | _ -> 0) in
       if offset > 0 then
         (match String.split_on_char '\n' str with
          | _ :: rest -> "{\n" ^ String.concat "\n" (List.map (fun l -> String.make offset ' ' ^ l) rest)
          | [] -> str)
       else str
     with _ -> s_null)

and pad ?(padding = Noval) ?(padchar = Noval) s =
  let s = (match s with Str x -> x | Null -> "null" | _ -> stringify s) in
  let padding = (match padding with Num n -> int_of_float n | _ -> 44) in
  let padchar = (match padchar with Str x -> String.sub (x ^ " ") 0 1 | _ -> " ") in
  if padding > -1 then
    let n = padding - String.length s in
    if n > 0 then s ^ String.concat "" (List.init n (fun _ -> padchar)) else s
  else
    let n = (- padding) - String.length s in
    if n > 0 then String.concat "" (List.init n (fun _ -> padchar)) ^ s else s

and join ?(sep = Noval) ?(url = false) arr =
  if not (islist arr) then s_mt
  else begin
    let sepdef = (match sep with Noval | Null -> "," | Str s -> s | _ -> js_string sep) in
    let single = (String.length sepdef = 1) in
    let sc = if single then sepdef.[0] else ' ' in
    let items_ = (match arr with List r -> !r | _ -> []) in
    let sarr = List.length items_ in
    let strip_trailing s = let n = String.length s in let i = ref n in
      while !i > 0 && s.[!i - 1] = sc do decr i done; String.sub s 0 !i in
    let strip_leading s = let n = String.length s in let i = ref 0 in
      while !i < n && s.[!i] = sc do incr i done; String.sub s !i (n - !i) in
    (* Collapse runs of the sep char to one, but only when the run is bounded
       by a non-sep char on both sides (mirrors ([^sep])sep+([^sep])). Boundary
       runs (leading / trailing) are left untouched. *)
    let collapse s =
      let n = String.length s in
      let b = Buffer.create n in
      let i = ref 0 in
      while !i < n do
        if s.[!i] <> sc then (Buffer.add_char b s.[!i]; incr i)
        else begin
          let j = ref !i in
          while !j < n && s.[!j] = sc do incr j done;
          let before_nonsep = !i > 0 && s.[!i - 1] <> sc in
          let after_nonsep = !j < n in
          if before_nonsep && after_nonsep then Buffer.add_char b sc
          else Buffer.add_string b (String.sub s !i (!j - !i));
          i := !j
        end
      done;
      Buffer.contents b in
    let out = ref [] in
    List.iteri (fun idx s0 ->
        match s0 with
        | Str s when s <> s_mt ->
          let s =
            if single then begin
              if url && idx = 0 then strip_trailing s
              else begin
                let s = if idx > 0 then strip_leading s else s in
                let s = if idx < sarr - 1 || not url then strip_trailing s else s in
                collapse s
              end
            end else s
          in
          if s <> s_mt then out := s :: !out
        | _ -> ()) items_;
    String.concat sepdef (List.rev !out)
  end

and joinurl arr = join ~sep:(Str "/") ~url:true arr

and replace s from_ to_ =
  let ts = typify s in
  let rs =
    if (t_string land ts) = 0 then stringify s
    else if ((t_noval lor t_null) land ts) > 0 then s_mt
    else stringify s in
  let to_s = (match to_ with Str x -> x | _ -> js_string to_) in
  match from_ with
  | Str f ->
    (* replace all occurrences *)
    if f = "" then rs
    else begin
      let b = Buffer.create (String.length rs) in
      let flen = String.length f in let i = ref 0 in let n = String.length rs in
      while !i < n do
        if !i + flen <= n && String.sub rs !i flen = f then (Buffer.add_string b to_s; i := !i + flen)
        else (Buffer.add_char b rs.[!i]; incr i)
      done; Buffer.contents b
    end
  | _ -> rs

and pathify ?(startin = Noval) ?(endin = Noval) ?(absent = false) v =
  let path =
    if islist v then Some (match v with List r -> !r | _ -> [])
    else if iskey v then Some [v]
    else None in
  let start = (match startin with Num n -> if n > -1.0 then int_of_float n else 0 | _ -> 0) in
  let endn = (match endin with Num n -> if n > -1.0 then int_of_float n else 0 | _ -> 0) in
  let pathstr =
    match path with
    | Some p when start >= 0 ->
      let len = List.length p in
      let arr = Array.of_list p in
      let e = max 0 (len - endn) in
      let s = min start len in
      let sub = if s <= e then Array.to_list (Array.sub arr s (e - s)) else [] in
      if sub = [] then Some "<root>"
      else
        let fp = List.filter iskey sub in
        let mapped = List.map (fun pp ->
            match pp with
            | Num n -> num_to_string (Float.floor n)
            | _ -> String.concat "" (String.split_on_char '.' (js_string pp))) fp in
        Some (String.concat "." mapped)
    | _ -> None
  in
  match pathstr with
  | Some s -> s
  | None -> "<unknown-path" ^ (if absent then s_mt else s_cn ^ stringify ~maxlen:(Num 47.0) v) ^ ">"

(* ----- walk ----- *)

and walk ?before ?after ?maxdepth:(md = Noval) ?(key = Noval) ?(parent = Noval) ?path ?pool v =
  let pool = (match pool with Some p -> p | None -> [| ref [Noval] |] ) in
  ignore pool;
  walk_impl before after md key parent path v

and walk_impl before after md key parent path v =
  (* path is a string list ref shared per depth (we keep it simple: an int-indexed value list) *)
  let path = (match path with Some p -> p | None -> empty_list ()) in
  let depth = size path in
  let out = ref (match before with None -> v | Some f -> f key v parent path) in
  let mdv = (match md with Num n -> if n >= 0.0 then int_of_float n else maxdepth | Noval | Null -> maxdepth | _ -> maxdepth) in
  if mdv = 0 || (mdv > 0 && mdv <= depth) then !out
  else begin
    (if isnode !out then begin
        let prefix = (match path with List r -> !r | _ -> []) in
        List.iter (fun (ckey, child) ->
            let childpath = lst (prefix @ [Str ckey]) in
            let result = walk_impl before after (Num (float_of_int mdv)) (Str ckey) !out (Some childpath) child in
            (match !out with
             | Map m -> omap_set m ckey result
             | List r -> r := List.mapi (fun i x -> if i = int_of_string ckey then result else x) !r
             | _ -> ())) (items_pairs !out)
      end);
    (match after with None -> !out | Some f -> f key !out parent path)
  end

(* ----- merge ----- *)

and merge ?(maxdepth = Noval) objs =
  let md = (match maxdepth with Num n -> if n < 0.0 then 0 else int_of_float n | Noval | Null -> 32 | _ -> 32) in
  if not (islist objs) then objs
  else begin
    let l = (match objs with List r -> !r | _ -> []) in
    let lenlist = List.length l in
    if lenlist = 0 then Noval
    else if lenlist = 1 then List.nth l 0
    else begin
      let out = ref (getprop ~alt:(empty_map ()) objs (Num 0.0)) in
      for oi = 1 to lenlist - 1 do
        let obj = List.nth l oi in
        if not (isnode obj) then out := obj
        else begin
          let cur = ref [| !out |] in
          let dst = ref [| !out |] in
          let grow a n = if Array.length !a <= n then begin
              let na = Array.make (n + 1) Noval in
              Array.blit !a 0 na 0 (Array.length !a); a := na end in
          let before key v _parent path =
            let pi = size path in
            if md <= pi then begin
              grow cur pi; !cur.(pi) <- v;
              if pi > 0 then ignore (setprop !cur.(pi - 1) key v);
              Noval
            end else if not (isnode v) then begin
              grow cur pi; !cur.(pi) <- v; v
            end else begin
              grow dst pi; grow cur pi;
              !dst.(pi) <- (if pi > 0 then getprop !dst.(pi - 1) key else !dst.(pi));
              let tval = !dst.(pi) in
              if is_nullish tval then (!cur.(pi) <- (if islist v then empty_list () else empty_map ()); v)
              else if (islist v && islist tval) || (ismap v && ismap tval) then
                (!cur.(pi) <- tval; v)
              else (!cur.(pi) <- v; Noval)
            end
          in
          let after key _v _parent path =
            let ci = size path in
            if ci < 1 then (if Array.length !cur > 0 then !cur.(0) else _v)
            else begin
              let target = if ci - 1 < Array.length !cur then !cur.(ci - 1) else Noval in
              let value = if ci < Array.length !cur then !cur.(ci) else Noval in
              ignore (setprop target key value); value
            end
          in
          out := walk ~before ~after obj
        end
      done;
      if md = 0 then begin
        let o = getprop objs (Num (float_of_int (lenlist - 1))) in
        out := (if islist o then empty_list () else if ismap o then empty_map () else o)
      end;
      !out
    end
  end

(* ----- getpath / setpath ----- *)

and ia_base = function IInj i -> i.base | IDef d -> d.d_base | INone -> Noval
and ia_dparent = function IInj i -> i.dparent | IDef d -> d.d_dparent | INone -> Noval
and ia_meta = function IInj i -> i.meta | IDef d -> d.d_meta | INone -> Noval
and ia_key = function IInj i -> i.key | IDef d -> d.d_key | INone -> Noval
and ia_dpath = function IInj i -> i.dpath | IDef d -> d.d_dpath | INone -> Noval
and ia_handler = function IInj i -> Some i.handler | IDef d -> d.d_handler | INone -> None
and ia_is_some = function INone -> false | _ -> true

and getpath ?(inj = INone) store path =
  let pa =
    match path with
    | List r -> Some (Array.of_list !r)
    | Str s -> Some (Array.of_list (List.map (fun x -> Str x) (String.split_on_char '.' s)))
    | Num n -> Some [| Str (strkey ~key:(Num n) ()) |]
    | _ -> None
  in
  match pa with
  | None -> Noval
  | Some pa ->
    let base = ia_base inj in
    let dparent = ia_dparent inj in
    let inj_meta = ia_meta inj in
    let inj_key = ia_key inj in
    let dpath = ia_dpath inj in
    let src = if iskey base then getprop ~alt:store store base else store in
    let numparts = Array.length pa in
    let v = ref store in
    let arr_get i = if i >= 0 && i < Array.length pa then pa.(i) else Noval in
    (if is_noval path || is_noval store
        || (numparts = 1 && pa.(0) = Str s_mt) || numparts = 0 then
       v := src
     else begin
       if numparts = 1 then v := getprop store pa.(0);
       if not (isfunc !v) then begin
         v := src;
         (match pa.(0) with
          | Str s0 ->
            (match meta_path_match s0 with
             | Some (g1, _, g3) when not (is_noval inj_meta) && ia_is_some inj ->
               v := getprop inj_meta (Str g1); pa.(0) <- Str g3
             | _ -> ())
          | _ -> ());
         let pi = ref 0 in
         let continue = ref true in
         while !continue && not (is_noval !v) && !pi < numparts do
           let raw = pa.(!pi) in
           let part =
             match raw with
             | Str s when ia_is_some inj && s = s_dkey -> if not (is_noval inj_key) then inj_key else raw
             | Str s when starts_with s "$GET:" ->
               Str (stringify (getpath ~inj:INone src (slice ~start:(Num 5.0) ~stop:(Num (-1.0)) (Str s))))
             | Str s when starts_with s "$REF:" ->
               Str (stringify (getpath ~inj:INone (getprop store (Str s_dspec)) (slice ~start:(Num 5.0) ~stop:(Num (-1.0)) (Str s))))
             | Str s when ia_is_some inj && starts_with s "$META:" ->
               Str (stringify (getpath ~inj:INone inj_meta (slice ~start:(Num 6.0) ~stop:(Num (-1.0)) (Str s))))
             | _ -> raw
           in
           let part = (match part with
               | Str s -> Str (replace_all s "$$" "$")
               | _ -> Str (strkey ~key:part ())) in
           if part = Str s_mt then begin
             let ascends = ref 0 in
             while arr_get (!pi + 1) = Str s_mt do incr ascends; incr pi done;
             if ia_is_some inj && !ascends > 0 then begin
               if !pi = numparts - 1 then decr ascends;
               if !ascends = 0 then v := dparent
               else begin
                 let tailparts = Array.to_list (Array.sub pa (!pi + 1) (numparts - (!pi + 1))) in
                 let fullpath = flatten (lst [slice ~start:(Num (float_of_int (- !ascends))) dpath; lst tailparts]) in
                 v := (if !ascends <= size dpath then getpath ~inj:INone store fullpath else Noval);
                 continue := false
               end
             end else v := dparent
           end else v := getprop !v part;
           if !continue then incr pi
         done
       end
     end);
    (match ia_handler inj with
     | Some h when ia_is_some inj ->
       let refp = pathify path in
       (match inj with
        | IInj i -> v := h i !v refp store
        | _ -> v := h (Option.get !dummy_inj_ref) !v refp store)
     | _ -> ());
    !v

and setpath ?(inj = INone) store path v =
  let ptype = typify path in
  let parts =
    if (t_list land ptype) > 0 then (match path with List r -> lst !r | _ -> empty_list ())
    else if (t_string land ptype) > 0 then (match path with Str s -> lst (List.map (fun x -> Str x) (String.split_on_char '.' s)) | _ -> empty_list ())
    else if (t_number land ptype) > 0 then lst [path]
    else Noval
  in
  if is_noval parts then Noval
  else begin
    let base = (match inj with INone -> Noval | _ -> ia_base inj) in
    let numparts = size parts in
    let parent = ref (if iskey base then getprop ~alt:store store base else store) in
    for pi = 0 to numparts - 2 do
      let pkey = getelem parts (Num (float_of_int pi)) in
      let np = getprop !parent pkey in
      let np = if not (isnode np) then begin
          let nextpart = getelem parts (Num (float_of_int (pi + 1))) in
          let nn = if (t_number land typify nextpart) > 0 then empty_list () else empty_map () in
          ignore (setprop !parent pkey nn); nn
        end else np in
      parent := np
    done;
    if is_delete v then ignore (delprop !parent (getelem parts (Num (-1.0))))
    else ignore (setprop !parent (getelem parts (Num (-1.0))) v);
    !parent
  end

(* ----- string-pattern helpers (hand-rolled, RE2-subset-free) ----- *)

and starts_with s pre =
  String.length s >= String.length pre && String.sub s 0 (String.length pre) = pre

and replace_all s find_ repl =
  if find_ = "" then s
  else begin
    let b = Buffer.create (String.length s) in
    let flen = String.length find_ in let n = String.length s in let i = ref 0 in
    while !i < n do
      if !i + flen <= n && String.sub s !i flen = find_ then (Buffer.add_string b repl; i := !i + flen)
      else (Buffer.add_char b s.[!i]; incr i)
    done; Buffer.contents b
  end

(* R_META_PATH = ^([^$]+)\$([=~])(.+)$ *)
and meta_path_match s =
  match String.index_opt s '$' with
  | Some i when i > 0 && i + 1 < String.length s
                && (s.[i + 1] = '=' || s.[i + 1] = '~')
                && i + 2 <= String.length s - 1 ->
    Some (String.sub s 0 i, String.make 1 s.[i + 1], String.sub s (i + 2) (String.length s - i - 2))
  | _ -> None

(* R_INJECTION_FULL: whole string is a single backtick injection; returns the
   captured reference ($NAME with trailing digits stripped, or the literal). *)
and injection_full s =
  let n = String.length s in
  if n >= 2 && s.[0] = '`' && s.[n - 1] = '`' then begin
    let inner = String.sub s 1 (n - 2) in
    if String.contains inner '`' then None
    else begin
      (* $[A-Z]+[0-9]*$ -> group is $ + uppercase run *)
      let is_dollar_upper =
        String.length inner > 1 && inner.[0] = '$' &&
        (let j = ref 1 in
         while !j < String.length inner && inner.[!j] >= 'A' && inner.[!j] <= 'Z' do incr j done;
         let letters_end = !j in
         letters_end > 1 &&
         (let k = ref letters_end in
          while !k < String.length inner && inner.[!k] >= '0' && inner.[!k] <= '9' do incr k done;
          !k = String.length inner))
      in
      if is_dollar_upper then begin
        let j = ref 1 in
        while !j < String.length inner && inner.[!j] >= 'A' && inner.[!j] <= 'Z' do incr j done;
        Some (String.sub inner 0 !j)
      end else Some inner
    end
  end else None

(* replace each `...` (R_INJECTION_PARTIAL) using f on the inner text *)
and injection_partial_replace s f =
  let n = String.length s in
  let b = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    if s.[!i] = '`' then begin
      match String.index_from_opt s (!i + 1) '`' with
      | Some j ->
        let inner = String.sub s (!i + 1) (j - !i - 1) in
        Buffer.add_string b (f inner);
        i := j + 1
      | None -> Buffer.add_char b s.[!i]; incr i
    end else (Buffer.add_char b s.[!i]; incr i)
  done;
  Buffer.contents b

(* replace `$NAME` -> name (lowercase), used in validate error descriptions *)
and replace_transform_names s =
  let n = String.length s in
  let b = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    if s.[!i] = '`' && !i + 1 < n && s.[!i + 1] = '$' then begin
      let j = ref (!i + 2) in
      while !j < n && s.[!j] >= 'A' && s.[!j] <= 'Z' do incr j done;
      if !j < n && s.[!j] = '`' && !j > !i + 2 then begin
        Buffer.add_string b (String.lowercase_ascii (String.sub s (!i + 2) (!j - !i - 2)));
        i := !j + 1
      end else (Buffer.add_char b s.[!i]; incr i)
    end else (Buffer.add_char b s.[!i]; incr i)
  done;
  Buffer.contents b

(* ----- Injection ----- *)

and new_inj v parent =
  { mode = m_val; full = false; keyi = 0;
    keys = lst [Str s_dtop]; key = Str s_dtop; ival = v; parent;
    path = lst [Str s_dtop]; nodes = lst [parent]; handler = inject_handler;
    errs = empty_list (); meta = empty_map (); dparent = Noval; dpath = lst [Str s_dtop];
    base = Str s_dtop; modify = None; prior = None; extra = Noval }

and inj_descend inj =
  (match inj.meta with Map m ->
    let d = (match omap_get m "__d" with Some (Num n) -> n | _ -> 0.0) in
    omap_set m "__d" (Num (d +. 1.0)) | _ -> ());
  let parentkey = getelem inj.path (Num (-2.0)) in
  if is_noval inj.dparent then begin
    if size inj.dpath > 1 then
      inj.dpath <- (match inj.dpath, parentkey with List r, _ -> lst (!r @ [parentkey]) | _ -> inj.dpath)
  end else if not (is_noval parentkey) then begin
    inj.dparent <- getprop inj.dparent parentkey;
    let lastpart = getelem inj.dpath (Num (-1.0)) in
    if lastpart = Str ("$:" ^ js_string parentkey) then
      inj.dpath <- slice ~start:(Num (-1.0)) inj.dpath
    else inj.dpath <- (match inj.dpath with List r -> lst (!r @ [parentkey]) | _ -> inj.dpath)
  end;
  inj.dparent

and inj_child inj keyi keys =
  let key = strkey ~key:(getelem keys (Num (float_of_int keyi))) () in
  let v = inj.ival in
  let cinj = {
    mode = inj.mode; full = inj.full; keyi; keys; key = Str key;
    ival = getprop v (Str key); parent = v;
    path = (match inj.path with List r -> lst (!r @ [Str key]) | _ -> lst [Str key]);
    nodes = (match inj.nodes with List r -> lst (!r @ [v]) | _ -> lst [v]);
    handler = inj.handler; errs = inj.errs; meta = inj.meta; base = inj.base;
    modify = inj.modify; prior = Some inj;
    dpath = (match inj.dpath with List r -> lst !r | _ -> inj.dpath);
    dparent = inj.dparent; extra = inj.extra;
  } in
  cinj

and inj_setval ?(ancestor = 1) inj v =
  let target, key =
    if ancestor < 2 then inj.parent, inj.key
    else getelem inj.nodes (Num (float_of_int (- ancestor))), getelem inj.path (Num (float_of_int (- ancestor)))
  in
  if is_noval v then delprop target key else setprop target key v

(* ----- inject ----- *)

and inject ?(inj = INone) v store =
  let state =
    match inj with
    | IInj i -> i
    | _ ->
      let parent = Map { entries = [(s_dtop, v)] } in
      let i = new_inj v parent in
      i.dparent <- store;
      i.errs <- getprop ~alt:(empty_list ()) store (Str s_derrs);
      (match i.meta with Map m -> omap_set m "__d" (Num 0.0) | _ -> ());
      (match inj with
       | IDef d ->
         (match d.d_modify with Some _ -> i.modify <- d.d_modify | None -> ());
         (if not (is_noval d.d_extra) then i.extra <- d.d_extra);
         (if not (is_noval d.d_meta) then i.meta <- d.d_meta);
         (match d.d_handler with Some h -> i.handler <- h | None -> ())
       | _ -> ());
      i
  in
  ignore (inj_descend state);
  let v =
    if isnode v then begin
      let nodekeys = ref (
        match v with
        | Map m ->
          let ks = List.map fst m.entries in
          let normal = List.sort compare (List.filter (fun k -> not (String.contains k '$')) ks) in
          let trans = List.sort compare (List.filter (fun k -> String.contains k '$') ks) in
          normal @ trans
        | List r -> List.mapi (fun i _ -> string_of_int i) !r
        | _ -> [])
      in
      let nki = ref 0 in
      let continue = ref true in
      while !continue && !nki < List.length !nodekeys do
        let childinj = inj_child state !nki (lst (List.map (fun s -> Str s) !nodekeys)) in
        let nodekey = childinj.key in
        childinj.mode <- m_keypre;
        let prekey = injectstr (js_string nodekey) store (Some childinj) in
        nodekeys := List.map js_string (match childinj.keys with List r -> !r | _ -> []);
        (if not (is_noval prekey) then begin
            childinj.ival <- getprop v prekey;
            childinj.mode <- m_val;
            ignore (inject ~inj:(IInj childinj) childinj.ival store);
            nodekeys := List.map js_string (match childinj.keys with List r -> !r | _ -> []);
            childinj.mode <- m_keypost;
            ignore (injectstr (js_string nodekey) store (Some childinj));
            nodekeys := List.map js_string (match childinj.keys with List r -> !r | _ -> [])
          end);
        nki := childinj.keyi + 1;
        ignore continue
      done;
      v
    end else if (match v with Str _ -> true | _ -> false) then begin
      state.mode <- m_val;
      let nv = injectstr (js_string v) store (Some state) in
      (if not (is_skip nv) then ignore (inj_setval state nv));
      nv
    end else v
  in
  (match state.modify with
   | Some f when not (is_skip v) ->
     let mkey = state.key in let mparent = state.parent in let mval = getprop mparent mkey in
     f mval mkey mparent state
   | _ -> ());
  state.ival <- v;
  lookup_ state.parent (Str s_dtop)

and inject_handler inj v refstr store =
  let iscmd = isfunc v && (refstr = "" || starts_with refstr s_ds) in
  if iscmd then (match v with Func f -> f inj v refstr store | _ -> v)
  else if state_mode_is_val inj && inj.full then (ignore (inj_setval inj v); v)
  else v

and state_mode_is_val inj = (inj.mode = m_val)

and injectstr v store inj_opt =
  if v = s_mt then Str s_mt
  else begin
    match injection_full v with
    | Some pathref0 ->
      (match inj_opt with Some i -> i.full <- true | None -> ());
      let pathref = if String.length pathref0 > 3 then
          replace_all (replace_all pathref0 "$BT" s_bt) "$DS" s_ds else pathref0 in
      let ia = (match inj_opt with Some i -> IInj i | None -> INone) in
      let out = getpath ~inj:ia store (Str pathref) in
      (* out may be any value, returned as the injected value *)
      out_to_val out
    | None ->
      let out = injection_partial_replace v (fun ref0 ->
          let refp = if String.length ref0 > 3 then
              replace_all (replace_all ref0 "$BT" s_bt) "$DS" s_ds else ref0 in
          (match inj_opt with Some i -> i.full <- false | None -> ());
          let ia = (match inj_opt with Some i -> IInj i | None -> INone) in
          let found = getpath ~inj:ia store (Str refp) in
          match found with
          | Noval -> s_mt
          | Str s -> if s = "__NULL__" then "null" else s
          | Func _ -> s_mt
          | _ -> (try json_encode found with _ -> stringify found))
      in
      (match inj_opt with
       | Some i when isfunc_handler i ->
         i.full <- true; out_to_val (i.handler i (Str out) v store)
       | _ -> Str out)
  end

and out_to_val v = v
and isfunc_handler _i = true

(* ----- transform commands ----- *)

and transform_delete inj _v _ref _store = ignore (delprop inj.parent inj.key); Noval

and transform_copy inj _v _ref _store =
  if inj.mode = m_keypre || inj.mode = m_keypost then inj.key
  else begin
    let out = lookup_ inj.dparent inj.key in
    ignore (inj_setval inj out); out
  end

and transform_key inj _v _ref _store =
  if inj.mode <> m_val then Noval
  else begin
    let keyspec = lookup_ inj.parent (Str s_bkey) in
    if not (is_noval keyspec) then (ignore (delprop inj.parent (Str s_bkey)); getprop inj.dparent keyspec)
    else
      let anno = lookup_ inj.parent (Str s_banno) in
      let fromanno = lookup_ anno (Str s_key) in
      if not (is_noval fromanno) then fromanno
      else getelem inj.path (Num (-2.0))
  end

and transform_anno inj _v _ref _store = ignore (delprop inj.parent (Str s_banno)); Noval

and transform_merge inj _v _ref _store =
  if inj.mode = m_keypre then inj.key
  else if inj.mode = m_keypost then begin
    let args0 = getprop inj.parent inj.key in
    let args = if islist args0 then args0 else lst [args0] in
    ignore (inj_setval inj Noval);
    let mergelist = flatten (lst [lst [inj.parent]; args; lst [clone inj.parent]]) in
    ignore (merge mergelist);
    inj.key
  end else Noval

and transform_each inj _v _ref store =
  (if islist inj.keys then ignore (slice ~start:(Num 0.0) ~stop:(Num 1.0) ~mutate:true inj.keys));
  if inj.mode <> m_val then Noval
  else begin
    let parent = inj.parent in
    let srcpath = if size parent > 1 then getelem parent (Num 1.0) else Noval in
    let child_tm = if size parent > 2 then clone (getelem parent (Num 2.0)) else Noval in
    let srcstore = getprop ~alt:store store inj.base in
    let src = getpath ~inj:(IInj inj) srcstore srcpath in
    let tkey = getelem inj.path (Num (-2.0)) in
    let nodes = inj.nodes in
    let target =
      let t = getelem nodes (Num (-2.0)) in
      if is_nullish t then getelem nodes (Num (-1.0)) else t in
    let tval = ref [] in
    let rval = ref (empty_list ()) in
    (if isnode src then begin
        (match src with
         | List r -> List.iter (fun _ -> tval := clone child_tm :: !tval) !r
         | Map m -> List.iter (fun (k, _) ->
             let cc = clone child_tm in
             (if ismap cc then ignore (setprop cc (Str s_banno) (Map { entries = [(s_key, Str k)] })));
             tval := cc :: !tval) m.entries
         | _ -> ());
        let tvall = List.rev !tval in
        let tvalv = lst tvall in
        let tcurrent = (match src with
            | Map m -> lst (List.map snd m.entries)
            | List r -> lst !r | _ -> src) in
        if List.length tvall > 0 then begin
          let path = inj.path in
          let ckey = getelem path (Num (-2.0)) in
          let plist = (match path with List r -> !r | _ -> []) in
          let tpath = lst (if plist = [] then [] else List.filteri (fun i _ -> i < List.length plist - 1) plist) in
          let dpath = ref [Str s_dtop] in
          (match srcpath with Str sp when sp <> s_mt ->
            List.iter (fun p -> if p <> s_mt then dpath := !dpath @ [Str p]) (String.split_on_char '.' sp)
                                | _ -> ());
          (if not (is_noval ckey) then dpath := !dpath @ [Str ("$:" ^ js_string ckey)]);
          let tcur = ref (Map { entries = [(js_string ckey, tcurrent)] }) in
          (if size tpath > 1 then begin
              let pkey = getelem ~alt:(Str s_dtop) path (Num (-3.0)) in
              dpath := !dpath @ [Str ("$:" ^ js_string pkey)];
              tcur := Map { entries = [(js_string pkey, !tcur)] }
            end);
          let tinj = inj_child inj 0 (if not (is_noval ckey) then lst [ckey] else empty_list ()) in
          tinj.path <- tpath;
          let nlist = (match nodes with List r -> !r | _ -> []) in
          tinj.nodes <- lst (if nlist = [] then [] else List.filteri (fun i _ -> i < List.length nlist - 1) nlist);
          tinj.parent <- (if size tinj.nodes > 0 then getelem tinj.nodes (Num (-1.0)) else Noval);
          (if not (is_noval ckey) && not (is_noval tinj.parent) then ignore (setprop tinj.parent ckey tvalv));
          tinj.ival <- tvalv;
          tinj.dpath <- lst !dpath;
          tinj.dparent <- !tcur;
          ignore (inject ~inj:(IInj tinj) tvalv store);
          rval := tinj.ival
        end
      end);
    ignore (setprop target tkey !rval);
    if islist !rval && size !rval > 0 then getelem !rval (Num 0.0) else Noval
  end

and transform_pack inj _v _ref store =
  if inj.mode <> m_keypre || not (match inj.key with Str _ -> true | _ -> false) then Noval
  else begin
    let parent = inj.parent in let path = inj.path in let nodes = inj.nodes in
    let args_val = getprop parent inj.key in
    if not (islist args_val) || size args_val < 2 then Noval
    else begin
      let srcpath = getelem args_val (Num 0.0) in
      let origchildspec = getelem args_val (Num 1.0) in
      let tkey = getelem path (Num (-2.0)) in
      let pathsize = size path in
      let target =
        let t = getelem nodes (Num (float_of_int (pathsize - 2))) in
        if is_nullish t then getelem nodes (Num (float_of_int (pathsize - 1))) else t in
      let srcstore = getprop ~alt:store store inj.base in
      let src0 = getpath ~inj:(IInj inj) srcstore srcpath in
      let src =
        if not (islist src0) then
          (if ismap src0 then
             lst (List.map (fun (k, node) ->
                 ignore (setprop node (Str s_banno) (Map { entries = [(s_key, Str k)] })); node)
                 (items_pairs src0))
           else Noval)
        else src0 in
      if is_noval src then Noval
      else begin
        let keypath = getprop origchildspec (Str s_bkey) in
        let childspec = delprop origchildspec (Str s_bkey) in
        let child = getprop ~alt:childspec childspec (Str s_bval) in
        let tval = empty_map () in
        List.iter (fun (srckey, srcnode) ->
            let k =
              if is_noval keypath then Str srckey
              else (match keypath with
                  | Str kp when starts_with kp s_bt ->
                    inject (Str kp) (merge ~maxdepth:(Num 1.0) (lst [empty_map (); store; Map { entries = [(s_dtop, srcnode)] }]))
                  | _ -> getpath ~inj:(IInj inj) srcnode keypath) in
            let tchild = clone child in
            ignore (setprop tval k tchild);
            let anno = getprop srcnode (Str s_banno) in
            if is_noval anno then ignore (delprop tchild (Str s_banno))
            else ignore (setprop tchild (Str s_banno) anno)) (items_pairs src);
        let rval = ref (empty_map ()) in
        (if not (isempty tval) then begin
            let tsrc = empty_map () in
            List.iteri (fun i node ->
                let kn =
                  if is_noval keypath then vint i
                  else (match keypath with
                      | Str kp when starts_with kp s_bt ->
                        inject (Str kp) (merge ~maxdepth:(Num 1.0) (lst [empty_map (); store; Map { entries = [(s_dtop, node)] }]))
                      | _ -> getpath ~inj:(IInj inj) node keypath) in
                ignore (setprop tsrc kn node))
              (match src with List r -> !r | _ -> []);
            let tpath = slice ~start:(Num (-1.0)) inj.path in
            let ckey = getelem inj.path (Num (-2.0)) in
            let dpath = ref [Str s_dtop] in
            (match srcpath with Str sp ->
              List.iter (fun p -> if p <> s_mt then dpath := !dpath @ [Str p]) (String.split_on_char '.' sp)
                                  | _ -> ());
            dpath := !dpath @ [Str ("$:" ^ js_string ckey)];
            let tcur = ref (Map { entries = [(js_string ckey, tsrc)] }) in
            (if size tpath > 1 then begin
                let pkey = getelem ~alt:(Str s_dtop) inj.path (Num (-3.0)) in
                dpath := !dpath @ [Str ("$:" ^ js_string pkey)];
                tcur := Map { entries = [(js_string pkey, !tcur)] }
              end);
            let tinj = inj_child inj 0 (lst [ckey]) in
            tinj.path <- tpath;
            tinj.nodes <- slice ~start:(Num (-1.0)) inj.nodes;
            tinj.parent <- getelem tinj.nodes (Num (-1.0));
            tinj.ival <- tval;
            tinj.dpath <- lst !dpath;
            tinj.dparent <- !tcur;
            ignore (inject ~inj:(IInj tinj) tval store);
            rval := tinj.ival
          end);
        ignore (setprop target tkey !rval);
        Noval
      end
    end
  end

and transform_ref inj v _ref store =
  if inj.mode <> m_val then Noval
  else begin
    let nodes = inj.nodes in
    let refpath = lookup_ inj.parent (Num 1.0) in
    inj.keyi <- size inj.keys;
    let spec_func = getprop store (Str s_dspec) in
    (match spec_func with
     | Func f ->
       let spec = f inj Noval "" Noval in
       let refv = getpath ~inj:INone spec refpath in
       let has_sub = ref false in
       (if isnode refv then ignore (walk ~before:(fun _k v2 _p _path -> (if v2 = Str "`$REF`" then has_sub := true); v2) refv));
       let tref = clone refv in
       let cpath = slice ~start:(Num 0.0) ~stop:(Num (float_of_int (size inj.path - 3))) inj.path in
       let tpath = slice ~start:(Num 0.0) ~stop:(Num (float_of_int (size inj.path - 1))) inj.path in
       let tcur = getpath ~inj:INone store cpath in
       let tval = getpath ~inj:INone store tpath in
       let rval = ref Noval in
       (if not (is_noval refv) && (not !has_sub || not (is_noval tval)) then begin
           let cs = inj_child inj 0 (lst [getelem tpath (Num (-1.0))]) in
           cs.path <- tpath;
           cs.nodes <- slice ~start:(Num 0.0) ~stop:(Num (float_of_int (size inj.nodes - 1))) inj.nodes;
           cs.parent <- getelem nodes (Num (-2.0));
           cs.ival <- tref;
           cs.dparent <- tcur;
           ignore (inject ~inj:(IInj cs) tref store);
           rval := cs.ival
         end);
       ignore (inj_setval ~ancestor:2 inj !rval);
       (match inj.prior with
        | Some p when islist inj.parent -> p.keyi <- p.keyi - 1
        | _ -> ());
       v
     | _ -> Noval)
  end

and jsstr v = match v with Null -> "null" | Bool b -> if b then "true" else "false" | _ -> js_string v

and formatter_tbl = [
  ("identity", (fun _k v -> v));
  ("upper", (fun _k v -> if isnode v then v else Str (String.uppercase_ascii (jsstr v))));
  ("lower", (fun _k v -> if isnode v then v else Str (String.lowercase_ascii (jsstr v))));
  ("string", (fun _k v -> if isnode v then v else Str (jsstr v)));
  ("number", (fun _k v -> if isnode v then v else
                 let n = (try float_of_string (jsstr v) with _ -> 0.0) in
                 let n = if Float.is_nan n then 0.0 else n in Num n));
  ("integer", (fun _k v -> if isnode v then v else
                  let n = (try float_of_string (jsstr v) with _ -> 0.0) in
                  let n = if Float.is_nan n then 0.0 else n in Num (Float.of_int (int_of_float n))));
  ("concat", (fun k v -> if is_noval k && islist v then
                 Str (join ~sep:(Str s_mt) (items_v v (fun (_, x) -> if isnode x then Str s_mt else Str (jsstr x))))
               else v));
]

and check_placement modes ijname parenttypes inj =
  let modenum = inj.mode in
  if (modes land modenum) = 0 then begin
    let allowed = List.filter (fun m -> (modes land m) <> 0) [m_keypre; m_keypost; m_val] in
    let placements = String.concat "," (List.map (fun m -> if m = m_val then "value" else "key") allowed) in
    let cur = if modenum = m_val then "value" else "key" in
    ignore (setprop inj.errs (Num (float_of_int (size inj.errs))) (Str (Printf.sprintf "$%s: invalid placement as %s, expected: %s." ijname cur placements)));
    false
  end else if not (isempty (Num (float_of_int parenttypes))) then begin
    let ptype = typify inj.parent in
    if (parenttypes land ptype) = 0 then begin
      ignore (setprop inj.errs (Num (float_of_int (size inj.errs)))
                (Str (Printf.sprintf "$%s: invalid placement in parent %s, expected: %s." ijname (typename ptype) (typename parenttypes))));
      false
    end else true
  end else true

and injector_args argtypes args =
  let numargs = List.length argtypes in
  let found = Array.make (1 + numargs) Noval in
  let err = ref None in
  (try
     List.iteri (fun argi at ->
         let arg = getelem args (Num (float_of_int argi)) in
         let argtype = typify arg in
         if (at land argtype) = 0 then begin
           found.(0) <- Str (Printf.sprintf "invalid argument: %s (%s at position %d) is not of type: %s."
                               (stringify ~maxlen:(Num 22.0) arg) (typename argtype) (1 + argi) (typename at));
           err := Some (); raise Exit
         end else found.(1 + argi) <- arg) argtypes
   with Exit -> ());
  ignore !err;
  Array.to_list found

and inject_child child store inj =
  let cinj = ref inj in
  (match inj.prior with
   | Some prior ->
     (match prior.prior with
      | Some pprior ->
        let c = inj_child pprior prior.keyi prior.keys in
        c.ival <- child; ignore (setprop c.parent prior.key child); cinj := c
      | None ->
        let c = inj_child prior inj.keyi inj.keys in
        c.ival <- child; ignore (setprop c.parent inj.key child); cinj := c)
   | None -> ());
  ignore (inject ~inj:(IInj !cinj) child store);
  !cinj

and transform_format inj _v _ref store =
  ignore (slice ~start:(Num 0.0) ~stop:(Num 1.0) ~mutate:true inj.keys);
  if inj.mode <> m_val then Noval
  else begin
    let name = lookup_ inj.parent (Num 1.0) in
    let child = lookup_ inj.parent (Num 2.0) in
    let tkey = getelem inj.path (Num (-2.0)) in
    let target = let t = getelem inj.nodes (Num (-2.0)) in if is_nullish t then getelem inj.nodes (Num (-1.0)) else t in
    let cinj = inject_child child store inj in
    let resolved = cinj.ival in
    let formatter =
      if (t_function land typify name) > 0 then
        Some (fun k v -> match name with Func f -> f (Option.get !dummy_inj_ref) v (js_string k) Noval | _ -> v)
      else (match List.assoc_opt (js_string name) formatter_tbl with Some f -> Some f | None -> None)
    in
    match formatter with
    | None -> ignore (setprop inj.errs (Num (float_of_int (size inj.errs))) (Str (Printf.sprintf "$FORMAT: unknown format: %s." (js_string name)))); Noval
    | Some f ->
      let out = walk ~before:(fun k v _p _path -> f k v) resolved in
      ignore (setprop target tkey out); out
  end

and transform_apply inj _v _ref store =
  if not (check_placement m_val "APPLY" t_list inj) then Noval
  else begin
    let res = injector_args [t_function; t_any] (slice ~start:(Num 1.0) inj.parent) in
    let err = List.nth res 0 in
    let apply_fn = List.nth res 1 in
    let child = if List.length res > 2 then List.nth res 2 else Noval in
    if not (is_noval err) then (ignore (setprop inj.errs (Num (float_of_int (size inj.errs))) (Str ("$APPLY: " ^ js_string err))); Noval)
    else begin
      let tkey = getelem inj.path (Num (-2.0)) in
      let target = let t = getelem inj.nodes (Num (-2.0)) in if is_nullish t then getelem inj.nodes (Num (-1.0)) else t in
      let cinj = inject_child child store inj in
      let resolved = cinj.ival in
      let out = (match apply_fn with Func f -> f cinj resolved "" store | _ -> Noval) in
      ignore (setprop target tkey out); out
    end
  end

and transform ?(inj = INone) data spec =
  let origspec = spec in
  let spec = clone spec in
  let extra = (match inj with IDef d -> d.d_extra | _ -> Noval) in
  let collect = (match inj with IDef d -> not (is_noval d.d_errs) | _ -> false) in
  let errs = (match inj with IDef d when collect -> d.d_errs | _ -> empty_list ()) in
  let extra_transforms = empty_map () in
  let extra_data = empty_map () in
  (if not (is_noval extra) then
     List.iter (fun (k, v) ->
         if starts_with k s_ds then ignore (setprop extra_transforms (Str k) v)
         else ignore (setprop extra_data (Str k) v)) (items_pairs extra));
  let data_clone = merge (lst [(if isempty extra_data then Noval else clone extra_data); clone data]) in
  let store = empty_map () in
  let put k v = ignore (setprop store (Str k) v) in
  put s_dtop data_clone;
  put s_dspec (Func (fun _ _ _ _ -> origspec));
  put "$BT" (Func (fun _ _ _ _ -> Str s_bt));
  put "$DS" (Func (fun _ _ _ _ -> Str s_ds));
  put "$WHEN" (Func (fun _ _ _ _ -> Str "1970-01-01T00:00:00.000Z"));
  put "$DELETE" (Func transform_delete);
  put "$COPY" (Func transform_copy);
  put "$KEY" (Func transform_key);
  put "$ANNO" (Func transform_anno);
  put "$MERGE" (Func transform_merge);
  put "$EACH" (Func transform_each);
  put "$PACK" (Func transform_pack);
  put "$REF" (Func transform_ref);
  put "$FORMAT" (Func transform_format);
  put "$APPLY" (Func transform_apply);
  List.iter (fun (k, v) -> put k v) (items_pairs extra_transforms);
  put s_derrs errs;
  let idef = { (default_injdef ()) with d_errs = errs } in
  (match inj with
   | IDef d ->
     idef.d_meta <- d.d_meta; idef.d_modify <- d.d_modify; idef.d_handler <- d.d_handler;
     idef.d_base <- d.d_base
   | _ -> ());
  let out = inject ~inj:(IDef idef) spec store in
  if size errs > 0 && not collect then raise (Struct_error (join ~sep:(Str " | ") errs));
  out

and default_injdef () =
  { d_meta = Noval; d_extra = Noval; d_errs = Noval; d_modify = None; d_handler = None;
    d_base = Noval; d_dparent = Noval; d_dpath = Noval; d_key = Noval }

(* ----- validate ----- *)

and invalid_type_msg path needtype vt v _whence =
  let vs = if is_nullish v then "no value" else stringify v in
  "Expected "
  ^ (if size path > 1 then "field " ^ pathify ~startin:(Num 1.0) path ^ " to be " else "")
  ^ needtype ^ ", but found "
  ^ (if not (is_nullish v) then typename vt ^ s_viz else "")
  ^ vs ^ "."

and validate_string inj _v _ref _store =
  let out = lookup_ inj.dparent inj.key in
  let t = typify out in
  if (t_string land t) = 0 then (push_err inj (invalid_type_msg inj.path s_string t out "V1010"); Noval)
  else if out = Str s_mt then (push_err inj ("Empty string at " ^ pathify ~startin:(Num 1.0) inj.path); Noval)
  else out

and push_err inj msg = ignore (setprop inj.errs (Num (float_of_int (size inj.errs))) (Str msg))

and validate_type inj _v refstr _store =
  let tname = if String.length refstr > 1 then String.lowercase_ascii (String.sub refstr 1 (String.length refstr - 1)) else "any" in
  let idx = (let r = ref (-1) in Array.iteri (fun i x -> if x = tname && !r < 0 then r := i) typename_tbl; !r) in
  let typev0 = if idx >= 0 then 1 lsl (31 - idx) else 0 in
  let typev = if tname = s_nil then typev0 lor t_null else typev0 in
  let out = lookup_ inj.dparent inj.key in
  let t = typify out in
  if (t land typev) = 0 then (push_err inj (invalid_type_msg inj.path tname t out "V1001"); Noval)
  else out

and validate_any inj _v _ref _store = lookup_ inj.dparent inj.key

and validate_child inj _v _ref _store =
  let parent = inj.parent in let key = inj.key in let path = inj.path in let keys = inj.keys in
  if inj.mode = m_keypre then begin
    let childtm = getprop parent key in
    let pkey = getelem path (Num (-2.0)) in
    let tval = getprop inj.dparent pkey in
    if is_noval tval then begin
      List.iter (fun ckey -> ignore (setprop parent (Str ckey) (clone childtm)); ignore (setprop keys (Num (float_of_int (size keys))) (Str ckey))) (keysof (empty_map ()));
      ignore (delprop parent key); Noval
    end else if not (ismap tval) then
      (push_err inj (invalid_type_msg (slice ~start:(Num 0.0) ~stop:(Num (float_of_int (size path - 1))) path) s_object (typify tval) tval "V0220"); Noval)
    else begin
      List.iter (fun ckey -> ignore (setprop parent (Str ckey) (clone childtm)); ignore (setprop keys (Num (float_of_int (size keys))) (Str ckey))) (keysof tval);
      ignore (delprop parent key); Noval
    end
  end else if inj.mode = m_val then begin
    let childtm = getprop parent (Num 1.0) in
    if not (islist parent) then (push_err inj "Invalid $CHILD as value"; Noval)
    else if is_noval inj.dparent then (match parent with List r -> r := []; Noval | _ -> Noval)
    else if not (islist inj.dparent) then begin
      push_err inj (invalid_type_msg (slice ~start:(Num 0.0) ~stop:(Num (float_of_int (size path - 1))) path) s_list (typify inj.dparent) inj.dparent "V0230");
      inj.keyi <- size parent; inj.dparent
    end else begin
      List.iter (fun (k, _) -> ignore (setprop parent (Str k) (clone childtm))) (items_pairs inj.dparent);
      (match parent with List r -> let n = size inj.dparent in r := (let a = Array.of_list !r in Array.to_list (Array.sub a 0 (min n (Array.length a)))) | _ -> ());
      inj.keyi <- 0;
      getprop inj.dparent (Num 0.0)
    end
  end else Noval

and validate_one inj _v _ref store =
  if inj.mode = m_val then begin
    let parent = inj.parent in
    if not (islist parent) || inj.keyi <> 0 then
      (push_err inj ("The $ONE validator at field " ^ pathify ~startin:(Num 1.0) ~endin:(Num 1.0) inj.path ^ " must be the first element of an array."); Noval)
    else begin
      inj.keyi <- size inj.keys;
      ignore (inj_setval ~ancestor:2 inj inj.dparent);
      inj.path <- slice ~start:(Num 0.0) ~stop:(Num (float_of_int (size inj.path - 1))) inj.path;
      inj.key <- getelem inj.path (Num (-1.0));
      let tvals = slice ~start:(Num 1.0) parent in
      if size tvals = 0 then
        (push_err inj ("The $ONE validator at field " ^ pathify ~startin:(Num 1.0) ~endin:(Num 1.0) inj.path ^ " must have at least one argument."); Noval)
      else begin
        let matched = ref false in
        List.iter (fun tval ->
            if not !matched then begin
              let terrs = empty_list () in
              let vstore = merge ~maxdepth:(Num 1.0) (lst [empty_map (); store]) in
              ignore (setprop vstore (Str s_dtop) inj.dparent);
              let idef = { (default_injdef ()) with d_extra = vstore; d_errs = terrs; d_meta = inj.meta } in
              let vcurrent = validate ~inj:(IDef idef) inj.dparent tval in
              ignore (inj_setval ~ancestor:(-2) inj vcurrent);
              if size terrs = 0 then matched := true
            end) (match tvals with List r -> !r | _ -> []);
        if not !matched then begin
          let valdesc = String.concat ", " (List.map (fun (_, x) -> stringify x) (items_pairs tvals)) in
          let valdesc = replace_transform_names valdesc in
          push_err inj (invalid_type_msg inj.path ((if size tvals > 1 then "one of " else "") ^ valdesc) (typify inj.dparent) inj.dparent "V0210")
        end;
        Noval
      end
    end
  end else Noval

and validate_exact inj _v _ref _store =
  if inj.mode = m_val then begin
    let parent = inj.parent in
    if not (islist parent) || inj.keyi <> 0 then
      (push_err inj ("The $EXACT validator at field " ^ pathify ~startin:(Num 1.0) ~endin:(Num 1.0) inj.path ^ " must be the first element of an array."); Noval)
    else begin
      inj.keyi <- size inj.keys;
      ignore (inj_setval ~ancestor:2 inj inj.dparent);
      inj.path <- slice ~start:(Num 0.0) ~stop:(Num (float_of_int (size inj.path - 1))) inj.path;
      inj.key <- getelem inj.path (Num (-1.0));
      let tvals = slice ~start:(Num 1.0) parent in
      if size tvals = 0 then
        (push_err inj ("The $EXACT validator at field " ^ pathify ~startin:(Num 1.0) ~endin:(Num 1.0) inj.path ^ " must have at least one argument."); Noval)
      else begin
        let matched = ref false in
        List.iter (fun tval -> if not !matched && veq tval inj.dparent then matched := true)
          (match tvals with List r -> !r | _ -> []);
        if not !matched then begin
          let valdesc = String.concat ", " (List.map (fun (_, x) -> stringify x) (items_pairs tvals)) in
          let valdesc = replace_transform_names valdesc in
          push_err inj (invalid_type_msg inj.path
                          ((if size inj.path > 1 then "" else "value ") ^ "exactly equal to " ^ (if size tvals = 1 then "" else "one of ") ^ valdesc)
                          (typify inj.dparent) inj.dparent "V0110")
        end;
        Noval
      end
    end
  end else (ignore (delprop inj.parent inj.key); Noval)

and veq a b =
  match a, b with
  | Noval, Noval -> true
  | Null, Null -> true
  | Bool x, Bool y -> x = y
  | Num x, Num y -> x = y
  | Str x, Str y -> x = y
  | Sentinel x, Sentinel y -> x = y
  | List x, List y -> List.length !x = List.length !y && List.for_all2 veq !x !y
  | Map x, Map y ->
    omap_len x = omap_len y &&
    List.for_all (fun (k, v) -> match omap_get y k with Some w -> veq v w | None -> false) x.entries
  | _ -> false

and validation pval key parent inj =
  if not (is_skip pval) then begin
    let exact = getprop ~alt:(Bool false) inj.meta (Str s_bexact) in
    let cval = getprop inj.dparent key in
    let exact_b = (match exact with Bool true -> true | _ -> false) in
    if not ((not exact_b) && is_noval cval) then begin
      let ptype = typify pval in
      if not ((t_string land ptype) > 0 && String.contains (js_string pval) '$') then begin
        let ctype = typify cval in
        if ptype <> ctype && not (is_noval pval) then
          push_err inj (invalid_type_msg inj.path (typename ptype) ctype cval "V0010")
        else if ismap cval then begin
          if not (ismap pval) then push_err inj (invalid_type_msg inj.path (typename ptype) ctype cval "V0020")
          else begin
            let ckeys = keysof cval in
            let pkeys = keysof pval in
            if List.length pkeys > 0 && not (getprop pval (Str s_bopen) = Bool true) then begin
              let badkeys = List.filter (fun ck -> is_noval (lookup_ pval (Str ck))) ckeys in
              if List.length badkeys > 0 then
                push_err inj ("Unexpected keys at field " ^ pathify ~startin:(Num 1.0) inj.path ^ s_viz ^ String.concat ", " badkeys)
            end else begin
              ignore (merge (lst [pval; cval]));
              if isnode pval then ignore (delprop pval (Str s_bopen))
            end
          end
        end else if islist cval then
          (if not (islist pval) then push_err inj (invalid_type_msg inj.path (typename ptype) ctype cval "V0030"))
        else if exact_b then
          (if not (veq cval pval) then
             let pathmsg = if size inj.path > 1 then "at field " ^ pathify ~startin:(Num 1.0) inj.path ^ ": " else "" in
             push_err inj ("Value " ^ pathmsg ^ js_string cval ^ " should equal " ^ js_string pval ^ "."))
        else ignore (setprop parent key cval)
      end
    end
  end

and validate_handler inj v refstr store =
  match meta_path_match refstr with
  | Some (_, g2, _) ->
    (if g2 = "=" then ignore (inj_setval inj (lst [Str s_bexact; v])) else ignore (inj_setval inj v));
    inj.keyi <- -1; skip
  | None -> inject_handler inj v refstr store

and validate ?(inj = INone) data spec =
  let extra = (match inj with IDef d -> d.d_extra | _ -> Noval) in
  let collect = (match inj with IDef d -> not (is_noval d.d_errs) | _ -> false) in
  let errs = (match inj with IDef d when collect -> d.d_errs | _ -> empty_list ()) in
  let base = empty_map () in
  let put k v = ignore (setprop base (Str k) v) in
  List.iter (fun k -> put k Null) ["$DELETE"; "$COPY"; "$KEY"; "$META"; "$MERGE"; "$EACH"; "$PACK"];
  put "$STRING" (Func validate_string);
  List.iter (fun k -> put k (Func validate_type))
    ["$NUMBER"; "$INTEGER"; "$DECIMAL"; "$BOOLEAN"; "$NULL"; "$NIL"; "$MAP"; "$LIST"; "$FUNCTION"; "$INSTANCE"];
  put "$ANY" (Func validate_any);
  put "$CHILD" (Func validate_child);
  put "$ONE" (Func validate_one);
  put "$EXACT" (Func validate_exact);
  let store = merge ~maxdepth:(Num 1.0) (lst [base; (if is_noval extra then empty_map () else extra); Map { entries = [(s_derrs, errs)] }]) in
  let meta = (match inj with IDef d when not (is_noval d.d_meta) -> d.d_meta | _ -> empty_map ()) in
  ignore (setprop meta (Str s_bexact) (getprop ~alt:(Bool false) meta (Str s_bexact)));
  let idef = { (default_injdef ()) with d_meta = meta; d_extra = store; d_modify = Some validation; d_handler = Some validate_handler; d_errs = errs } in
  let out = transform ~inj:(IDef idef) data spec in
  if size errs > 0 && not collect then raise (Struct_error (join ~sep:(Str " | ") errs));
  out

(* ----- select ----- *)

and select_and inj _v _ref store =
  (if inj.mode = m_keypre then begin
      let terms = getprop inj.parent inj.key in
      let ppath = slice ~start:(Num (-1.0)) inj.path in
      let point = getpath ~inj:INone store ppath in
      let vstore = merge ~maxdepth:(Num 1.0) (lst [empty_map (); store]) in
      ignore (setprop vstore (Str s_dtop) point);
      List.iter (fun (_, term) ->
          let terrs = empty_list () in
          let idef = { (default_injdef ()) with d_extra = vstore; d_errs = terrs; d_meta = inj.meta } in
          ignore (validate ~inj:(IDef idef) point term);
          if size terrs <> 0 then push_err inj ("AND:" ^ pathify ppath ^ "\xe2\xa8\xaf" ^ stringify point ^ " fail:" ^ stringify terms)) (items_pairs terms);
      let gkey = getelem inj.path (Num (-2.0)) in
      let gp = getelem inj.nodes (Num (-2.0)) in
      ignore (setprop gp gkey point)
    end); Noval

and select_or inj _v _ref store =
  (if inj.mode = m_keypre then begin
      let terms = getprop inj.parent inj.key in
      let ppath = slice ~start:(Num (-1.0)) inj.path in
      let point = getpath ~inj:INone store ppath in
      let vstore = merge ~maxdepth:(Num 1.0) (lst [empty_map (); store]) in
      ignore (setprop vstore (Str s_dtop) point);
      let done_ = ref false in
      List.iter (fun (_, term) ->
          if not !done_ then begin
            let terrs = empty_list () in
            let idef = { (default_injdef ()) with d_extra = vstore; d_errs = terrs; d_meta = inj.meta } in
            ignore (validate ~inj:(IDef idef) point term);
            if size terrs = 0 then begin
              let gkey = getelem inj.path (Num (-2.0)) in
              let gp = getelem inj.nodes (Num (-2.0)) in
              ignore (setprop gp gkey point); done_ := true
            end
          end) (items_pairs terms);
      if not !done_ then push_err inj ("OR:" ^ pathify ppath ^ "\xe2\xa8\xaf" ^ stringify point ^ " fail:" ^ stringify terms)
    end); Noval

and select_not inj _v _ref store =
  (if inj.mode = m_keypre then begin
      let term = getprop inj.parent inj.key in
      let ppath = slice ~start:(Num (-1.0)) inj.path in
      let point = getpath ~inj:INone store ppath in
      let vstore = merge ~maxdepth:(Num 1.0) (lst [empty_map (); store]) in
      ignore (setprop vstore (Str s_dtop) point);
      let terrs = empty_list () in
      let idef = { (default_injdef ()) with d_extra = vstore; d_errs = terrs; d_meta = inj.meta } in
      ignore (validate ~inj:(IDef idef) point term);
      if size terrs = 0 then push_err inj ("NOT:" ^ pathify ppath ^ "\xe2\xa8\xaf" ^ stringify point ^ " fail:" ^ stringify term);
      let gkey = getelem inj.path (Num (-2.0)) in
      let gp = getelem inj.nodes (Num (-2.0)) in
      ignore (setprop gp gkey point)
    end); Noval

and num_cmp a b op =
  match a, b with
  | Num x, Num y -> (match op with `Gt -> x > y | `Lt -> x < y | `Gte -> x >= y | `Lte -> x <= y)
  | _ -> false

and select_cmp inj _v refstr store =
  (if inj.mode = m_keypre then begin
      let term = getprop inj.parent inj.key in
      let gkey = getelem inj.path (Num (-2.0)) in
      let ppath = slice ~start:(Num (-1.0)) inj.path in
      let point = getpath ~inj:INone store ppath in
      let pass =
        if refstr = "$GT" then num_cmp point term `Gt
        else if refstr = "$LT" then num_cmp point term `Lt
        else if refstr = "$GTE" then num_cmp point term `Gte
        else if refstr = "$LTE" then num_cmp point term `Lte
        else if refstr = "$LIKE" then (match term with Str t -> Vregex.test_str t (stringify point) | _ -> false)
        else false in
      if pass then (let gp = getelem inj.nodes (Num (-2.0)) in ignore (setprop gp gkey point))
      else push_err inj ("CMP: " ^ pathify ppath ^ "\xe2\xa8\xaf" ^ stringify point ^ " fail:" ^ refstr ^ " " ^ stringify term)
    end); Noval

and select children query =
  if not (isnode children) then empty_list ()
  else begin
    let children =
      if ismap children then
        lst (List.map (fun (k, n) -> ignore (setprop n (Str s_dkey) (Str k)); n) (items_pairs children))
      else
        lst (List.mapi (fun i n -> if ismap n then (ignore (setprop n (Str s_dkey) (vint i)); n) else n)
               (match children with List r -> !r | _ -> [])) in
    let results = empty_list () in
    let extra = empty_map () in
    List.iter (fun (k, f) -> ignore (setprop extra (Str k) (Func f)))
      [("$AND", select_and); ("$OR", select_or); ("$NOT", select_not);
       ("$GT", select_cmp); ("$LT", select_cmp); ("$GTE", select_cmp); ("$LTE", select_cmp); ("$LIKE", select_cmp)];
    let q = clone query in
    ignore (walk ~before:(fun _k v _p _path -> (if ismap v then ignore (setprop v (Str s_bopen) (getprop ~alt:(Bool true) v (Str s_bopen)))); v) q);
    List.iter (fun child ->
        let errs = empty_list () in
        let idef = { (default_injdef ()) with d_errs = errs; d_meta = (let m = empty_map () in ignore (setprop m (Str s_bexact) (Bool true)); m); d_extra = extra } in
        ignore (validate ~inj:(IDef idef) child (clone q));
        if size errs = 0 then ignore (setprop results (Num (float_of_int (size results))) child))
      (match children with List r -> !r | _ -> []);
    results
  end

(* ----- builders ----- *)

and jm kv =
  let m = empty_map () in
  let arr = Array.of_list kv in
  let n = Array.length arr in
  let i = ref 0 in
  while !i < n do
    let k0 = arr.(!i) in
    let k = (match k0 with Null -> "null" | Str s -> s | _ -> stringify k0) in
    omap_set (match m with Map mm -> mm | _ -> assert false) k (if !i + 1 < n then arr.(!i + 1) else Null);
    i := !i + 2
  done; m

and jt v = lst v

(* ---------------------------------------------------------------------------
 * Finish: set the dummy inj for getelem's function-alt path
 * ------------------------------------------------------------------------- *)

let () =
  let parent = Map { entries = [(s_dtop, Noval)] } in
  dummy_inj_ref := Some (new_inj Noval parent)

let tn = typename
