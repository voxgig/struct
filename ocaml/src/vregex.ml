(* Minimal backtracking regex engine for the OCaml port of voxgig/struct.
 * Supports the RE2 subset the corpus exercises: literals, '.', anchors ^ $,
 * word boundaries (b and B forms), character classes [..] / [^..] with ranges
 * and \d \w \s \D \W \S, groups (..), (?:..) and (?P<name>..), alternation |,
 * quantifiers * + ? and {n}/{n,}/{n,m} with optional lazy '?'. Capturing
 * groups are tracked, so the engine backs the full re_* API (find with
 * captures, find_all, replace) at the Go-stdlib minimum bar; `test` also
 * serves $LIKE. No third-party dependency. *)

type node =
  | Char of char
  | Any
  | Start
  | End
  | WordB
  | NWordB
  | Cls of bool * citem list           (* negated?, items *)
  | Grp of int * node list list        (* capture index (0 = non-capturing), alternation *)
  | Star of bool * node                (* greedy?, atom *)
  | Plus of bool * node
  | Opt of bool * node
  | Rep of bool * int * int option * node

and citem =
  | CChar of char
  | CRange of char * char
  | CD | CW | CS | CND | CNW | CNS     (* d w s D W S escapes *)

(* Compiled = the alternation AST plus the number of capturing groups. *)
type t = { alts : node list list; ngroups : int }

(* ----- parser ----- *)

let parse (pat : string) : t =
  let n = String.length pat in
  let pos = ref 0 in
  let gc = ref 0 in
  let peek () = if !pos < n then Some pat.[!pos] else None in
  let adv () = incr pos in
  let parse_class () =
    (* assumes current char is '[' *)
    adv ();
    let neg = (peek () = Some '^') in
    if neg then adv ();
    let items = ref [] in
    let finished = ref false in
    while not !finished do
      match peek () with
      | None -> finished := true
      | Some ']' -> adv (); finished := true
      | Some '\\' ->
        adv ();
        (match peek () with
         | Some 'd' -> items := CD :: !items; adv ()
         | Some 'w' -> items := CW :: !items; adv ()
         | Some 's' -> items := CS :: !items; adv ()
         | Some 'D' -> items := CND :: !items; adv ()
         | Some 'W' -> items := CNW :: !items; adv ()
         | Some 'S' -> items := CNS :: !items; adv ()
         | Some 'n' -> items := CChar '\n' :: !items; adv ()
         | Some 't' -> items := CChar '\t' :: !items; adv ()
         | Some 'r' -> items := CChar '\r' :: !items; adv ()
         | Some c -> items := CChar c :: !items; adv ()
         | None -> ())
      | Some c ->
        adv ();
        (* range? *)
        (match peek () with
         | Some '-' when (!pos + 1 < n && pat.[!pos + 1] <> ']') ->
           adv ();
           (match peek () with
            | Some c2 -> adv (); items := CRange (c, c2) :: !items
            | None -> items := CChar c :: !items)
         | _ -> items := CChar c :: !items)
    done;
    Cls (neg, List.rev !items)
  in
  let parse_quant_suffix atom =
    match peek () with
    | Some '*' -> adv ();
      let lazy_ = (peek () = Some '?') in if lazy_ then adv ();
      Some (Star (not lazy_, atom))
    | Some '+' -> adv ();
      let lazy_ = (peek () = Some '?') in if lazy_ then adv ();
      Some (Plus (not lazy_, atom))
    | Some '?' -> adv ();
      let lazy_ = (peek () = Some '?') in if lazy_ then adv ();
      Some (Opt (not lazy_, atom))
    | Some '{' ->
      (* {n} {n,} {n,m} *)
      let save = !pos in
      adv ();
      let num () =
        let b = Buffer.create 4 in
        let rec go () = match peek () with
          | Some c when c >= '0' && c <= '9' -> Buffer.add_char b c; adv (); go ()
          | _ -> () in
        go (); Buffer.contents b in
      let mn = num () in
      let mx =
        match peek () with
        | Some ',' -> adv (); let s = num () in if s = "" then None else Some (int_of_string s)
        | _ -> Some (if mn = "" then 0 else int_of_string mn)
      in
      (match peek () with
       | Some '}' when mn <> "" ->
         adv ();
         let lazy_ = (peek () = Some '?') in if lazy_ then adv ();
         Some (Rep (not lazy_, int_of_string mn, mx, atom))
       | _ -> pos := save; None)  (* not a valid quantifier; treat '{' literally *)
    | _ -> None
  in
  let rec parse_alt () : node list list =
    let first = parse_seq () in
    let alts = ref [first] in
    while peek () = Some '|' do
      adv ();
      alts := parse_seq () :: !alts
    done;
    List.rev !alts
  and parse_seq () : node list =
    let out = ref [] in
    let stop = ref false in
    while not !stop do
      match peek () with
      | None | Some '|' | Some ')' -> stop := true
      | _ ->
        let atom = parse_atom () in
        (match atom with
         | None -> stop := true
         | Some a ->
           let a = (match parse_quant_suffix a with Some q -> q | None -> a) in
           out := a :: !out)
    done;
    List.rev !out
  and parse_atom () : node option =
    match peek () with
    | None -> None
    | Some '(' ->
      adv ();
      (* (?: is non-capturing; a plain ( and an RE2 named group (?P<name> are
         both capturing (names are not tracked). Indices follow open parens. *)
      let gi =
        if peek () = Some '?' && !pos + 1 < n && pat.[!pos + 1] = ':' then (adv (); adv (); 0)
        else if peek () = Some '?' && !pos + 2 < n && pat.[!pos + 1] = 'P'
                && pat.[!pos + 2] = '<' then begin
          adv (); adv (); adv ();
          while peek () <> None && peek () <> Some '>' do adv () done;
          (if peek () = Some '>' then adv ());
          incr gc; !gc
        end
        else (incr gc; !gc)
      in
      let alts = parse_alt () in
      (if peek () = Some ')' then adv ());
      Some (Grp (gi, alts))
    | Some '[' -> Some (parse_class ())
    | Some '.' -> adv (); Some Any
    | Some '^' -> adv (); Some Start
    | Some '$' -> adv (); Some End
    | Some '\\' ->
      adv ();
      (match peek () with
       | Some 'd' -> adv (); Some (Cls (false, [CD]))
       | Some 'w' -> adv (); Some (Cls (false, [CW]))
       | Some 's' -> adv (); Some (Cls (false, [CS]))
       | Some 'D' -> adv (); Some (Cls (false, [CND]))
       | Some 'W' -> adv (); Some (Cls (false, [CNW]))
       | Some 'S' -> adv (); Some (Cls (false, [CNS]))
       | Some 'b' -> adv (); Some WordB
       | Some 'B' -> adv (); Some NWordB
       | Some 'n' -> adv (); Some (Char '\n')
       | Some 't' -> adv (); Some (Char '\t')
       | Some 'r' -> adv (); Some (Char '\r')
       | Some c -> adv (); Some (Char c)
       | None -> Some (Char '\\'))
    | Some c -> adv (); Some (Char c)
  in
  let alts = parse_alt () in
  { alts; ngroups = !gc }

(* ----- matcher (backtracking, CPS, capture-tracking) ----- *)

let is_word c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_'

let citem_match it c =
  match it with
  | CChar x -> c = x
  | CRange (a, b) -> c >= a && c <= b
  | CD -> c >= '0' && c <= '9'
  | CND -> not (c >= '0' && c <= '9')
  | CW -> is_word c
  | CNW -> not (is_word c)
  | CS -> c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\012' || c = '\011'
  | CNS -> not (c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\012' || c = '\011')

(* Capture spans, one slot per capturing group (group i at index i-1). The
   continuation receives the accepting end position and the spans so far; the
   first accepting continuation under backtracking order wins. Spans are
   threaded functionally (copy-on-write), so backtracking discards abandoned
   group records naturally. *)
type caps = (int * int) option array

let rec m_node input len node pos (caps : caps)
    (k : int -> caps -> (int * caps) option) : (int * caps) option =
  match node with
  | Char c -> if pos < len && input.[pos] = c then k (pos + 1) caps else None
  | Any -> if pos < len && input.[pos] <> '\n' then k (pos + 1) caps else None
  | Start -> if pos = 0 then k pos caps else None
  | End -> if pos = len then k pos caps else None
  | WordB ->
    let before = pos > 0 && is_word input.[pos - 1] in
    let after = pos < len && is_word input.[pos] in
    if before <> after then k pos caps else None
  | NWordB ->
    let before = pos > 0 && is_word input.[pos - 1] in
    let after = pos < len && is_word input.[pos] in
    if before = after then k pos caps else None
  | Cls (neg, items) ->
    if pos < len then begin
      let c = input.[pos] in
      let hit = List.exists (fun it -> citem_match it c) items in
      if (if neg then not hit else hit) then k (pos + 1) caps else None
    end else None
  | Grp (gi, alts) ->
    let k' =
      if gi = 0 then k
      else (fun p caps' ->
          let c2 = Array.copy caps' in
          c2.(gi - 1) <- Some (pos, p);
          k p c2)
    in
    first_alt input len alts pos caps k'
  | Opt (greedy, a) ->
    if greedy then
      (match m_node input len a pos caps k with Some r -> Some r | None -> k pos caps)
    else
      (match k pos caps with Some r -> Some r | None -> m_node input len a pos caps k)
  | Star (greedy, a) -> m_star input len greedy a pos caps k
  | Plus (greedy, a) ->
    m_node input len a pos caps (fun p c -> m_star input len greedy a p c k)
  | Rep (greedy, mn, mx, a) -> m_rep input len greedy mn mx a pos caps k

and first_alt input len alts pos caps k =
  match alts with
  | [] -> None
  | seq :: rest ->
    (match m_seq input len seq pos caps k with
     | Some r -> Some r
     | None -> first_alt input len rest pos caps k)

and m_star input len greedy a pos caps k =
  let more p c = if p > pos then m_star input len greedy a p c k else None in
  if greedy then
    (match m_node input len a pos caps more with Some r -> Some r | None -> k pos caps)
  else
    (match k pos caps with Some r -> Some r | None -> m_node input len a pos caps more)

and m_rep input len greedy mn mx a pos caps k =
  if mn > 0 then
    m_node input len a pos caps (fun p c ->
        m_rep input len greedy (mn - 1)
          (match mx with Some m -> Some (m - 1) | None -> None) a p c k)
  else
    match mx with
    | Some 0 -> k pos caps
    | _ ->
      let next p c = if p > pos then m_rep input len greedy 0
                       (match mx with Some m -> Some (m - 1) | None -> None) a p c k
        else None in
      if greedy then
        (match m_node input len a pos caps next with Some r -> Some r | None -> k pos caps)
      else
        (match k pos caps with Some r -> Some r | None -> m_node input len a pos caps next)

and m_seq input len seq pos caps k =
  match seq with
  | [] -> k pos caps
  | x :: rest -> m_node input len x pos caps (fun p c -> m_seq input len rest p c k)

let compile (pat : string) : t = parse pat

(* First match at or after `start`: (mstart, mend, caps). *)
let find_at (re : t) (input : string) (start : int) : (int * int * caps) option =
  let len = String.length input in
  let rec try_at i =
    if i > len then None
    else begin
      let caps0 = Array.make (max 1 re.ngroups) None in
      match first_alt input len re.alts i caps0 (fun p c -> Some (p, c)) with
      | Some (e, caps) -> Some (i, e, caps)
      | None -> try_at (i + 1)
    end
  in try_at start

(* Does the pattern match anywhere in input? *)
let test (re : t) (input : string) : bool =
  match find_at re input 0 with Some _ -> true | None -> false

let test_str (pat : string) (input : string) : bool = test (compile pat) input

(* Leftmost match: returns (start, stop) or None. *)
let find_bounds (re : t) (input : string) : (int * int) option =
  match find_at re input 0 with
  | Some (s, e, _) -> Some (s, e)
  | None -> None

let group_str input (caps : caps) gi =
  match caps.(gi) with
  | Some (a, b) -> String.sub input a (b - a)
  | None -> ""

let match_groups (re : t) input ms me caps =
  String.sub input ms (me - ms)
  :: List.init re.ngroups (fun i -> group_str input caps i)

(* First match as [whole; capture1; ...]; unmatched groups are "". *)
let find (re : t) (input : string) : string list option =
  match find_at re input 0 with
  | None -> None
  | Some (ms, me, caps) -> Some (match_groups re input ms me caps)

(* Every non-overlapping match, left to right (Go FindAllStringSubmatch). *)
let find_all (re : t) (input : string) : string list list =
  let len = String.length input in
  let rec go pos acc =
    if pos > len then List.rev acc
    else match find_at re input pos with
      | None -> List.rev acc
      | Some (ms, me, caps) ->
        let m = match_groups re input ms me caps in
        let pos' = if me = ms then me + 1 else me in
        go pos' (m :: acc)
  in
  go 0 []

(* Replace every match; the template supports the JS-style refs (and-sign for
   the whole match), 1..9 group refs and a doubled dollar for a literal
   dollar. On a zero-width match the current character is emitted and the
   scan advances one position. *)
let replace_all (re : t) (input : string) (template : string) : string =
  let len = String.length input in
  let b = Buffer.create (String.length input) in
  let tn = String.length template in
  let expand ms me (caps : caps) =
    let i = ref 0 in
    while !i < tn do
      let c = template.[!i] in
      if c = '$' && !i + 1 < tn then begin
        let nc = template.[!i + 1] in
        if nc = '$' then (Buffer.add_char b '$'; i := !i + 2)
        else if nc = '&' || (nc >= '0' && nc <= '9') then begin
          (if nc = '&' || nc = '0' then
             Buffer.add_string b (String.sub input ms (me - ms))
           else begin
             let gi = Char.code nc - Char.code '0' in
             if gi <= re.ngroups then
               (match caps.(gi - 1) with
                | Some (a, e) -> Buffer.add_string b (String.sub input a (e - a))
                | None -> ())
           end);
          i := !i + 2
        end else (Buffer.add_char b c; incr i)
      end else (Buffer.add_char b c; incr i)
    done
  in
  let rec go pos =
    if pos > len then ()
    else match find_at re input pos with
      | None -> Buffer.add_string b (String.sub input pos (len - pos))
      | Some (ms, me, caps) ->
        Buffer.add_string b (String.sub input pos (ms - pos));
        expand ms me caps;
        if me = ms then begin
          (if ms < len then Buffer.add_char b input.[ms]);
          go (ms + 1)
        end else go me
  in
  go 0;
  Buffer.contents b
