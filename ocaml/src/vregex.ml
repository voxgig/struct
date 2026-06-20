(* Minimal backtracking regex engine for the OCaml port of voxgig/struct.
 * Supports the RE2 subset the corpus exercises: literals, '.', anchors ^ $,
 * \b, character classes [..] / [^..] with ranges and \d \w \s \D \W \S,
 * groups (..) and (?:..), alternation |, quantifiers * + ? and {n}/{n,}/{n,m}
 * with optional lazy '?'. No third-party dependency. The struct library uses
 * `test` for $LIKE; `find` backs the public re_* API (not corpus-tested). *)

type node =
  | Char of char
  | Any
  | Start
  | End
  | WordB
  | Cls of bool * citem list           (* negated?, items *)
  | Grp of node list list              (* alternation of sequences *)
  | Star of bool * node                (* greedy?, atom *)
  | Plus of bool * node
  | Opt of bool * node
  | Rep of bool * int * int option * node

and citem =
  | CChar of char
  | CRange of char * char
  | CD | CW | CS | CND | CNW | CNS     (* \d \w \s \D \W \S *)

(* ----- parser ----- *)

let parse (pat : string) : node list list =
  let n = String.length pat in
  let pos = ref 0 in
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
      (* non-capturing? *)
      (if peek () = Some '?' && !pos + 1 < n && pat.[!pos + 1] = ':' then (adv (); adv ()));
      let alts = parse_alt () in
      (if peek () = Some ')' then adv ());
      Some (Grp alts)
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
       | Some 'n' -> adv (); Some (Char '\n')
       | Some 't' -> adv (); Some (Char '\t')
       | Some 'r' -> adv (); Some (Char '\r')
       | Some c -> adv (); Some (Char c)
       | None -> Some (Char '\\'))
    | Some c -> adv (); Some (Char c)
  in
  parse_alt ()

(* ----- matcher (backtracking, CPS) ----- *)

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

let rec m_node input len node pos (k : int -> bool) : bool =
  match node with
  | Char c -> pos < len && input.[pos] = c && k (pos + 1)
  | Any -> pos < len && input.[pos] <> '\n' && k (pos + 1)
  | Start -> pos = 0 && k pos
  | End -> pos = len && k pos
  | WordB ->
    let before = pos > 0 && is_word input.[pos - 1] in
    let after = pos < len && is_word input.[pos] in
    (before <> after) && k pos
  | Cls (neg, items) ->
    pos < len &&
    (let c = input.[pos] in
     let hit = List.exists (fun it -> citem_match it c) items in
     (if neg then not hit else hit) && k (pos + 1))
  | Grp alts -> List.exists (fun seq -> m_seq input len seq pos k) alts
  | Opt (greedy, a) ->
    if greedy then m_node input len a pos k || k pos
    else k pos || m_node input len a pos k
  | Star (greedy, a) -> m_star input len greedy a pos k
  | Plus (greedy, a) ->
    m_node input len a pos (fun p -> m_star input len greedy a p k)
  | Rep (greedy, mn, mx, a) -> m_rep input len greedy mn mx a pos k

and m_star input len greedy a pos k =
  if greedy then
    m_node input len a pos (fun p -> p > pos && m_star input len greedy a p k) || k pos
  else
    k pos || m_node input len a pos (fun p -> p > pos && m_star input len greedy a p k)

and m_rep input len greedy mn mx a pos k =
  if mn > 0 then
    m_node input len a pos (fun p ->
        m_rep input len greedy (mn - 1)
          (match mx with Some m -> Some (m - 1) | None -> None) a p k)
  else
    match mx with
    | Some 0 -> k pos
    | _ ->
      let next p = p > pos && m_rep input len greedy 0
                     (match mx with Some m -> Some (m - 1) | None -> None) a p k in
      if greedy then m_node input len a pos next || k pos
      else k pos || m_node input len a pos next

and m_seq input len seq pos k =
  match seq with
  | [] -> k pos
  | x :: rest -> m_node input len x pos (fun p -> m_seq input len rest p k)

(* Compiled = the alternation AST. *)
type t = node list list

let compile (pat : string) : t = parse pat

(* Does the pattern match anywhere in input? *)
let test (re : t) (input : string) : bool =
  let len = String.length input in
  let rec try_at i =
    if List.exists (fun seq -> m_seq input len seq i (fun _ -> true)) re then true
    else if i >= len then false
    else try_at (i + 1)
  in
  try_at 0

let test_str (pat : string) (input : string) : bool = test (compile pat) input

(* Leftmost match: returns (start, stop) or None. Used by the public re_* API. *)
let find_bounds (re : t) (input : string) : (int * int) option =
  let len = String.length input in
  let rec try_at i =
    if i > len then None
    else
      let best = ref (-1) in
      let ok = List.exists (fun seq -> m_seq input len seq i (fun p -> best := p; true)) re in
      if ok then Some (i, !best) else try_at (i + 1)
  in
  try_at 0
