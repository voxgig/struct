(* Test Provider (prototype) — OCaml port of the canonical ts/provider.ts.
 *
 * Reads the shared corpus (build/test/test.json) and hands test code clean,
 * normalized cases. It is NOT a test runner: it never calls the subject and
 * never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
 *
 * Zero runtime dependencies (OCaml stdlib only — NO yojson/findlib libs).
 * The JSON reader is adapted from ocaml/test/runner.ml's `json_read`, producing
 * the order-preserving `json` value type below.
 *
 * NOTE: This file has NOT been compiled or run — the OCaml toolchain is not
 * available in the authoring environment. It is a faithful, self-reviewed port. *)

let nullmark = "__NULL__"
let undefmark = "__UNDEF__"
let existsmark = "__EXISTS__"

(* ---------------- json value type ---------------- *)

(* Order-preserving: Obj is an association list, so functions()/groups() and
 * struct-match leaf walks observe corpus order. *)
type json =
  | Null
  | Bool of bool
  | Num of float
  | Str of string
  | Arr of json list
  | Obj of (string * json) list

(* Association-list helpers (order preserving). *)
let mem_assoc key = function
  | Obj kvs -> List.mem_assoc key kvs
  | _ -> false

let assoc_opt key = function
  | Obj kvs -> List.assoc_opt key kvs
  | _ -> None

(* ---------------- JSON reader -> json ----------------
 * Adapted from ocaml/test/runner.ml's json_read; same scanning structure,
 * retargeted to the local `json` type with order-preserving Obj. *)

let json_read (s : string) : json =
  let n = String.length s in
  let pos = ref 0 in
  let peek () = if !pos < n then Some s.[!pos] else None in
  let adv () = incr pos in
  let skip_ws () =
    while
      !pos < n
      && (match s.[!pos] with ' ' | '\t' | '\n' | '\r' -> true | _ -> false)
    do
      incr pos
    done
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
    if peek () = Some '}' then (adv (); Obj [])
    else begin
      let acc = ref [] in
      let rec loop () =
        skip_ws ();
        let k = pstr () in
        skip_ws (); adv (); (* : *)
        let v = pval () in
        acc := (k, v) :: !acc;
        skip_ws ();
        let c = (match peek () with Some c -> adv (); c | None -> '}') in
        if c = ',' then loop () else Obj (List.rev !acc)
      in
      loop ()
    end
  and parr () =
    adv (); skip_ws ();
    if peek () = Some ']' then (adv (); Arr [])
    else begin
      let acc = ref [] in
      let rec loop () =
        let v = pval () in
        acc := v :: !acc;
        skip_ws ();
        let c = (match peek () with Some c -> adv (); c | None -> ']') in
        if c = ',' then loop () else Arr (List.rev !acc)
      in
      loop ()
    end
  and pstr () =
    adv ();
    let b = Buffer.create 16 in
    let rec loop () =
      let c = s.[!pos] in
      adv ();
      if c = '"' then Buffer.contents b
      else if c = '\\' then begin
        let e = s.[!pos] in
        adv ();
        (match e with
         | '"' -> Buffer.add_char b '"'
         | '\\' -> Buffer.add_char b '\\'
         | '/' -> Buffer.add_char b '/'
         | 'n' -> Buffer.add_char b '\n'
         | 't' -> Buffer.add_char b '\t'
         | 'r' -> Buffer.add_char b '\r'
         | 'b' -> Buffer.add_char b '\b'
         | 'f' -> Buffer.add_char b '\012'
         | 'u' ->
           let hex = String.sub s !pos 4 in
           pos := !pos + 4;
           let code = int_of_string ("0x" ^ hex) in
           if code < 128 then Buffer.add_char b (Char.chr code)
           else if code < 2048 then begin
             Buffer.add_char b (Char.chr (0xC0 lor (code lsr 6)));
             Buffer.add_char b (Char.chr (0x80 lor (code land 0x3F)))
           end
           else begin
             Buffer.add_char b (Char.chr (0xE0 lor (code lsr 12)));
             Buffer.add_char b (Char.chr (0x80 lor ((code lsr 6) land 0x3F)));
             Buffer.add_char b (Char.chr (0x80 lor (code land 0x3F)))
           end
         | c -> Buffer.add_char b c);
        loop ()
      end
      else (Buffer.add_char b c; loop ())
    in
    loop ()
  and pnum () =
    let start = !pos in
    while
      !pos < n
      && (match s.[!pos] with
          | '0' .. '9' | '-' | '+' | '.' | 'e' | 'E' -> true
          | _ -> false)
    do
      incr pos
    done;
    let tok = String.sub s start (!pos - start) in
    Num (float_of_string tok)
  in
  pval ()

(* ---------------- normalized record types ---------------- *)

type input_kind = [ `In | `Args | `Ctx ]
type expect_kind = [ `Value | `Error | `Match | `Absent ]

type input = { kind : input_kind; value : json }

type error_check = { any : bool; text : string option; regex : bool }

type expect = {
  ekind : expect_kind;
  value : json option;        (* Some _ when kind = `Value (may be Some Null) *)
  error : error_check option;
  match_ : json option;       (* set whenever a "match" key co-exists *)
}

type entry = {
  function_ : string;
  group : string;
  index : int;
  id : string option;
  doc : bool;
  client : string option;
  input : input;
  expect : expect;
  raw : json;
}

(* struct_match result *)
type match_result = {
  ok : bool;
  path : string list;
  expected : json option;
  actual : json option;
}

(* ---------------- group / function classification ---------------- *)

(* A group bag is a map with a `set` array. *)
let is_group_bag (v : json) : bool =
  match v with
  | Obj kvs -> (match List.assoc_opt "set" kvs with Some (Arr _) -> true | _ -> false)
  | _ -> false

(* A function node has at least one child group bag (other than "name"). *)
let has_groups (v : json) : bool =
  match v with
  | Obj kvs ->
    List.exists (fun (k, child) -> k <> "name" && is_group_bag child) kvs
  | _ -> false

(* ---------------- normalization ---------------- *)

let json_to_string_opt (j : json) : string option =
  match j with
  | Null -> None
  | Str s -> Some s
  | Bool b -> Some (string_of_bool b)
  | Num f ->
    (* match JS String(): integral floats lose the trailing ".0" *)
    if Float.is_integer f && Float.abs f < 1e15 then
      Some (Printf.sprintf "%.0f" f)
    else Some (string_of_float f)
  | _ -> None

(* raw.x present and non-null -> Some (String(x)); else None. Mirrors
 * `null != raw.id ? String(raw.id) : null`. *)
let str_field raw key : string option =
  match assoc_opt key raw with
  | None | Some Null -> None
  | Some j -> json_to_string_opt j

let resolve_input (raw : json) : input =
  if mem_assoc "ctx" raw then
    { kind = `Ctx; value = (match assoc_opt "ctx" raw with Some v -> v | None -> Null) }
  else if mem_assoc "args" raw then
    { kind = `Args; value = (match assoc_opt "args" raw with Some v -> v | None -> Null) }
  else
    (* kind = `In; "in" key absent => native null (Null) *)
    { kind = `In; value = (match assoc_opt "in" raw with Some v -> v | None -> Null) }

let parse_err (err : json) : error_check =
  match err with
  | Bool true -> { any = true; text = None; regex = false }
  | Str s ->
    let len = String.length s in
    (* "/re/" — inner must be non-empty (matches /^\/(.+)\/$/) *)
    if len >= 3 && s.[0] = '/' && s.[len - 1] = '/' then
      { any = false; text = Some (String.sub s 1 (len - 2)); regex = true }
    else { any = false; text = Some s; regex = false }
  (* Non-true, non-string err spec: treat as "any error". *)
  | _ -> { any = true; text = None; regex = false }

let resolve_expect (raw : json) : expect =
  let match_part = if mem_assoc "match" raw then assoc_opt "match" raw else None in
  if mem_assoc "err" raw then
    {
      ekind = `Error;
      value = None;
      error = Some (parse_err (match assoc_opt "err" raw with Some v -> v | None -> Null));
      match_ = match_part;
    }
  else if mem_assoc "out" raw then
    (* KEY PRESENCE: "out" present even if Null => Value. *)
    {
      ekind = `Value;
      value = Some (match assoc_opt "out" raw with Some v -> v | None -> Null);
      error = None;
      match_ = match_part;
    }
  else if mem_assoc "match" raw then
    { ekind = `Match; value = None; error = None; match_ = match_part }
  else { ekind = `Absent; value = None; error = None; match_ = None }

let normalize fn group index (raw : json) : entry =
  {
    function_ = fn;
    group;
    index;
    id = str_field raw "id";
    doc = (match assoc_opt "doc" raw with Some (Bool true) -> true | _ -> false);
    client = str_field raw "client";
    input = resolve_input raw;
    expect = resolve_expect raw;
    raw;
  }

(* ---------------- TestProvider ---------------- *)

(* Default corpus path: build/test/test.json relative to the repo root.
 * This file lives at test/proto/ocaml, so up three levels reaches the root. *)
let default_test_file () : string =
  Filename.concat
    (Filename.dirname (Filename.dirname (Filename.dirname (Sys.getcwd ()))))
    (Filename.concat "build" (Filename.concat "test" "test.json"))

type provider = { spec : json }

(* The root holding functions: spec.struct if present, else spec itself. *)
let root_of (spec : json) : json =
  match assoc_opt "struct" spec with Some r -> r | None -> spec

let load ?path () : provider =
  let file =
    match path with
    | Some p -> p
    | None ->
      (* Prefer the conventional path relative to cwd if it exists, else the
       * repo-root-relative default. *)
      let cand = Filename.concat "build" (Filename.concat "test" "test.json") in
      if Sys.file_exists cand then cand
      else
        let d = default_test_file () in
        if Sys.file_exists d then d else cand
  in
  let ic = open_in_bin file in
  let len = in_channel_length ic in
  let raw = really_input_string ic len in
  close_in ic;
  { spec = json_read raw }

let raw (p : provider) : json = p.spec

let fn_node (p : provider) (fn : string) : json =
  let node =
    match assoc_opt fn (root_of p.spec) with
    | Some n -> Some n
    | None -> assoc_opt fn p.spec
  in
  match node with
  | Some n -> n
  | None -> failwith (Printf.sprintf "Unknown function: %s" fn)

let functions (p : provider) : string list =
  match root_of p.spec with
  | Obj kvs ->
    List.filter_map
      (fun (k, v) -> if is_group_bag v || has_groups v then Some k else None)
      kvs
  | _ -> []

let groups (p : provider) (fn : string) : string list =
  match fn_node p fn with
  | Obj kvs ->
    List.filter_map
      (fun (k, v) -> if k <> "name" && is_group_bag v then Some k else None)
      kvs
  | _ -> []

let entries ?group (p : provider) (fn : string) : entry list =
  let node = fn_node p fn in
  let gs = match group with Some g -> [ g ] | None -> groups p fn in
  let per_group g =
    match assoc_opt g node with
    | Some bag when is_group_bag bag -> (
        match assoc_opt "set" bag with
        | Some (Arr items) -> List.mapi (fun i it -> normalize fn g i it) items
        | _ -> [])
    | _ -> []
  in
  List.concat (List.map per_group gs)

(* ---------------- pure comparison helpers ---------------- *)

(* Compact JSON serialization (used by stringify for non-string values). *)
let rec json_compact (j : json) : string =
  match j with
  | Null -> "null"
  | Bool b -> string_of_bool b
  | Num f ->
    if Float.is_integer f && Float.abs f < 1e15 then Printf.sprintf "%.0f" f
    else
      (* JSON has no trailing-dot integers; OCaml's string_of_float gives "1."
       * for 1.0 but that branch is handled above. *)
      let s = Printf.sprintf "%.17g" f in
      s
  | Str s -> json_quote s
  | Arr xs -> "[" ^ String.concat "," (List.map json_compact xs) ^ "]"
  | Obj kvs ->
    "{"
    ^ String.concat ","
        (List.map (fun (k, v) -> json_quote k ^ ":" ^ json_compact v) kvs)
    ^ "}"

and json_quote (s : string) : string =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\t' -> Buffer.add_string b "\\t"
      | '\r' -> Buffer.add_string b "\\r"
      | '\b' -> Buffer.add_string b "\\b"
      | '\012' -> Buffer.add_string b "\\f"
      | c when Char.code c < 0x20 ->
        Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

(* stringify(x) = x if it is already a string, else compact JSON. *)
let stringify (x : json) : string =
  match x with Str s -> s | _ -> json_compact x

(* normNull: __NULL__ and absent collapse to Null (recursive). The provider's
 * json has no "absent" leaf, so only Str __NULL__ collapses here. *)
let rec norm_null (x : json) : json =
  match x with
  | Str s when s = nullmark -> Null
  | Arr xs -> Arr (List.map norm_null xs)
  | Obj kvs -> Obj (List.map (fun (k, v) -> (k, norm_null v)) kvs)
  | _ -> x

(* normMark: only __NULL__ -> Null (strict variant). *)
let rec norm_mark (x : json) : json =
  match x with
  | Str s when s = nullmark -> Null
  | Arr xs -> Arr (List.map norm_mark xs)
  | Obj kvs -> Obj (List.map (fun (k, v) -> (k, norm_mark v)) kvs)
  | _ -> x

(* Case-insensitive substring containment. *)
let contains_ci (hay : string) (needle : string) : bool =
  let low = String.lowercase_ascii in
  let hay = low hay and needle = low needle in
  let hl = String.length hay and nl = String.length needle in
  if nl = 0 then true
  else
    let rec go i =
      if i + nl > hl then false
      else if String.sub hay i nl = needle then true
      else go (i + 1)
    in
    go 0

(* Plain (case-sensitive) substring search — used by the simplified regex
 * fallback. *)
let contains_cs (hay : string) (needle : string) : bool =
  let hl = String.length hay and nl = String.length needle in
  if nl = 0 then true
  else
    let rec go i =
      if i + nl > hl then false
      else if String.sub hay i nl = needle then true
      else go (i + 1)
    in
    go 0

(* PROTOTYPE: regex simplified.
 * The canonical TS uses JS RegExp(text).test(str). To stay fully
 * dependency-free (no Str module / findlib lib), we approximate: an unanchored
 * pattern with no regex metacharacters is treated as a plain substring test;
 * anchors (^ / $) are honored against the trimmed literal. Patterns using other
 * metacharacters fall back to a literal substring test of the metachar-stripped
 * pattern. This is sufficient for the corpus's simple error/regex cases but is
 * NOT a full regex engine. *)
let regex_test (pat : string) (str : string) : bool =
  let plen = String.length pat in
  let anchored_start = plen > 0 && pat.[0] = '^' in
  let anchored_end = plen > 0 && pat.[plen - 1] = '$' in
  let core =
    let lo = if anchored_start then 1 else 0 in
    let hi = if anchored_end then plen - 1 else plen in
    if hi >= lo then String.sub pat lo (hi - lo) else ""
  in
  (* Strip simple metacharacters for the literal fallback. *)
  let is_meta = function
    | '.' | '*' | '+' | '?' | '(' | ')' | '[' | ']' | '{' | '}' | '|' | '\\' ->
      true
    | _ -> false
  in
  let str_exists pred s =
    let len = String.length s in
    let rec go i = i < len && (pred s.[i] || go (i + 1)) in
    go 0
  in
  let literal = String.length core > 0 && not (str_exists is_meta core) in
  if literal then
    if anchored_start && anchored_end then String.equal str core
    else if anchored_start then
      String.length str >= String.length core
      && String.sub str 0 (String.length core) = core
    else if anchored_end then
      let sl = String.length str and cl = String.length core in
      sl >= cl && String.sub str (sl - cl) cl = core
    else contains_cs str core
  else
    (* Metacharacter fallback: substring of the metachar-free remainder. *)
    let buf = Buffer.create (String.length core) in
    String.iter (fun c -> if not (is_meta c) then Buffer.add_char buf c) core;
    let stripped = Buffer.contents buf in
    if String.length stripped = 0 then true else contains_cs str stripped

(* Deep structural equality. Obj compared order-independently (key set + per-key
 * deep eq), Arr positionally. Mirrors deepEq in the canonical port; Bool/Num
 * never conflate (distinct json constructors). *)
let rec deep_eq (a : json) (b : json) : bool =
  match (a, b) with
  | Null, Null -> true
  | Bool x, Bool y -> x = y
  | Num x, Num y -> x = y
  | Str x, Str y -> String.equal x y
  | Arr xs, Arr ys ->
    List.length xs = List.length ys && List.for_all2 deep_eq xs ys
  | Obj xs, Obj ys ->
    List.length xs = List.length ys
    && List.for_all
         (fun (k, v) -> match List.assoc_opt k ys with Some w -> deep_eq v w | None -> false)
         xs
  | _ -> false

(* matchval(check, base): check === base; else string handling; else false.
 * (A function check would be `true`, but json has no function leaf.) *)
let matchval (check : json) (base : json) : bool =
  if deep_eq check base then true
  else
    match check with
    | Str cs ->
      let basestr = stringify base in
      let len = String.length cs in
      if len >= 3 && cs.[0] = '/' && cs.[len - 1] = '/' then
        regex_test (String.sub cs 1 (len - 2)) basestr
      else contains_ci basestr cs
    | _ -> false

let equal (expected : json) (actual : json) : bool =
  deep_eq (norm_null expected) (norm_null actual)

(* Strict variant for the runner's `{ null: false }` functions: only __NULL__
 * is normalized, native Null stays distinct. *)
let equal_strict (expected : json) (actual : json) : bool =
  deep_eq (norm_mark expected) (norm_mark actual)

let error_matches (check : error_check) (message : string) : bool =
  if check.any then true
  else
    match check.text with
    | None -> false
    | Some text -> if check.regex then regex_test text message else contains_ci message text

(* getpath over json. Returns None for an absent key/out-of-range index (the
 * provider's analogue of `undefined`); a present Null returns Some Null. *)
let getpath (store : json) (path : string list) : json option =
  let rec go cur = function
    | [] -> Some cur
    | key :: rest -> (
        match cur with
        | Obj kvs -> (match List.assoc_opt key kvs with Some v -> go v rest | None -> None)
        | Arr xs -> (
            match int_of_string_opt key with
            | Some i when i >= 0 && i < List.length xs -> go (List.nth xs i) rest
            | _ -> None)
        | Null -> None
        | _ -> None)
  in
  go store path

let is_node (v : json) : bool = match v with Obj _ | Arr _ -> true | _ -> false

(* Walk every leaf of `node`, invoking fn with (leaf, path). Object keys walked
 * in corpus (assoc-list) order; array indices as stringified positions. *)
let walk_leaves (node : json) (fn : json -> string list -> unit) : unit =
  let rec go node path =
    match node with
    | Arr xs -> List.iteri (fun i v -> go v (path @ [ string_of_int i ])) xs
    | Obj kvs -> List.iter (fun (k, v) -> go v (path @ [ k ])) kvs
    | _ -> fn node path
  in
  go node []

(* Partial structural match: every leaf of `check` must match `base` at its
 * path. First failure returns its path + the two values. *)
let struct_match (check : json) (base : json) : match_result =
  let result = ref { ok = true; path = []; expected = None; actual = None } in
  walk_leaves check (fun v path ->
      if (!result).ok then begin
        let baseval = getpath base path in
        let direct =
          match baseval with Some bv -> deep_eq bv v | None -> false
        in
        if direct then ()
        else if v = Str undefmark && baseval = None then ()
        else if
          v = Str existsmark
          && (match baseval with Some Null | None -> false | Some _ -> true)
        then ()
        else
          let compare_base = match baseval with Some bv -> bv | None -> Null in
          if not (matchval v compare_base) then
            result :=
              {
                ok = false;
                path;
                expected = Some v;
                actual = baseval;
              }
      end);
  !result
