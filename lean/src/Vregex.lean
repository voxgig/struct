/- Minimal backtracking regex engine for the Lean port of voxgig/struct.
   Supports the RE2 subset the corpus exercises: literals, '.', anchors ^ $,
   \b and \B, character classes [..] / [^..] with ranges and \d \w \s \D \W \S,
   groups (..), (?:..) and (?P<name>..), alternation |, quantifiers * + ? and
   {n}/{n,}/{n,m} with optional lazy '?'. No third-party dependency. The struct library uses
   `test` for $LIKE; `find` backs the public re_* API (not corpus-tested). -/

namespace Vregex

inductive CItem where
  | cchar (c : Char)
  | crange (a b : Char)
  | cd | cw | cs | cnd | cnw | cns     -- \d \w \s \D \W \S
  deriving Repr

inductive Node where
  | char (c : Char)
  | any
  | start
  | stop
  | wordb
  | nwordb
  | cls (neg : Bool) (items : List CItem)
  | grp (alts : List (List Node))      -- alternation of sequences
  | star (greedy : Bool) (atom : Node)
  | plus (greedy : Bool) (atom : Node)
  | opt (greedy : Bool) (atom : Node)
  | rep (greedy : Bool) (mn : Nat) (mx : Option Int) (atom : Node)
  deriving Repr

/- Compiled = the alternation AST. -/
abbrev Re := List (List Node)

-- ----- parser (over an Array Char) -----

private structure PState where
  pat : Array Char
  pos : Nat

private def peekAt (s : PState) (off : Nat := 0) : Option Char :=
  s.pat[s.pos + off]?

private def adv (s : PState) : PState := { s with pos := s.pos + 1 }

private def parseClass (s0 : PState) : Node × PState := Id.run do
  -- assumes current char is '['
  let mut s := adv s0
  let neg := peekAt s == some '^'
  if neg then s := adv s
  let mut items : List CItem := []
  let mut finished := false
  while !finished do
    match peekAt s with
    | none => finished := true
    | some ']' => s := adv s; finished := true
    | some '\\' =>
      s := adv s
      match peekAt s with
      | some 'd' => items := .cd :: items; s := adv s
      | some 'w' => items := .cw :: items; s := adv s
      | some 's' => items := .cs :: items; s := adv s
      | some 'D' => items := .cnd :: items; s := adv s
      | some 'W' => items := .cnw :: items; s := adv s
      | some 'S' => items := .cns :: items; s := adv s
      | some 'n' => items := .cchar '\n' :: items; s := adv s
      | some 't' => items := .cchar '\t' :: items; s := adv s
      | some 'r' => items := .cchar '\r' :: items; s := adv s
      | some c => items := .cchar c :: items; s := adv s
      | none => pure ()
    | some c =>
      s := adv s
      -- range?
      match peekAt s with
      | some '-' =>
        if peekAt s 1 != none && peekAt s 1 != some ']' then
          s := adv s
          match peekAt s with
          | some c2 => s := adv s; items := .crange c c2 :: items
          | none => items := .cchar c :: items
        else
          items := .cchar c :: items
      | _ => items := .cchar c :: items
  return (.cls neg items.reverse, s)

private def parseNum (s0 : PState) : String × PState := Id.run do
  let mut s := s0
  let mut b := ""
  let mut go := true
  while go do
    match peekAt s with
    | some c =>
      if c >= '0' && c <= '9' then b := b.push c; s := adv s
      else go := false
    | none => go := false
  return (b, s)

private def parseQuantSuffix (atom : Node) (s0 : PState) : Option (Node × PState) := Id.run do
  match peekAt s0 with
  | some '*' =>
    let s := adv s0
    let lzy := peekAt s == some '?'
    let s := if lzy then adv s else s
    return some (.star (!lzy) atom, s)
  | some '+' =>
    let s := adv s0
    let lzy := peekAt s == some '?'
    let s := if lzy then adv s else s
    return some (.plus (!lzy) atom, s)
  | some '?' =>
    let s := adv s0
    let lzy := peekAt s == some '?'
    let s := if lzy then adv s else s
    return some (.opt (!lzy) atom, s)
  | some '{' =>
    -- {n} {n,} {n,m}
    let s := adv s0
    let (mn, s) := parseNum s
    let (mx, s) :=
      match peekAt s with
      | some ',' =>
        let s := adv s
        let (mxs, s) := parseNum s
        ((if mxs == "" then none else some ((mxs.toNat?.getD 0 : Int))), s)
      | _ => (some ((mn.toNat?.getD 0 : Int)), s)
    match peekAt s with
    | some '}' =>
      if mn == "" then return none
      let s := adv s
      let lzy := peekAt s == some '?'
      let s := if lzy then adv s else s
      return some (.rep (!lzy) (mn.toNat?.getD 0) mx atom, s)
    | _ => return none  -- not a valid quantifier; treat '{' literally
  | _ => return none

mutual

partial def parseAlt (s0 : PState) : List (List Node) × PState := Id.run do
  let (first, s) := parseSeq s0
  let mut alts := [first]
  let mut s := s
  while peekAt s == some '|' do
    let (nxt, s') := parseSeq (adv s)
    alts := nxt :: alts
    s := s'
  return (alts.reverse, s)

partial def parseSeq (s0 : PState) : List Node × PState := Id.run do
  let mut out : List Node := []
  let mut s := s0
  let mut stop := false
  while !stop do
    match peekAt s with
    | none | some '|' | some ')' => stop := true
    | _ =>
      match parseAtom s with
      | none => stop := true
      | some (a, s') =>
        match parseQuantSuffix a s' with
        | some (q, s'') => out := q :: out; s := s''
        | none => out := a :: out; s := s'
  return (out.reverse, s)

partial def parseAtom (s0 : PState) : Option (Node × PState) :=
  match peekAt s0 with
  | none => none
  | some '(' =>
    let s := adv s0
    -- non-capturing (?: or RE2 named group (?P<name> — names are not tracked,
    -- both parse as a plain group
    let s :=
      if peekAt s == some '?' && peekAt s 1 == some ':' then adv (adv s)
      else if peekAt s == some '?' && peekAt s 1 == some 'P' && peekAt s 2 == some '<' then
        Id.run do
          let mut t := adv (adv (adv s))
          while peekAt t != none && peekAt t != some '>' do
            t := adv t
          if peekAt t == some '>' then return adv t else return t
      else s
    let (alts, s) := parseAlt s
    let s := if peekAt s == some ')' then adv s else s
    some (.grp alts, s)
  | some '[' => some (parseClass s0)
  | some '.' => some (.any, adv s0)
  | some '^' => some (.start, adv s0)
  | some '$' => some (.stop, adv s0)
  | some '\\' =>
    let s := adv s0
    match peekAt s with
    | some 'd' => some (.cls false [.cd], adv s)
    | some 'w' => some (.cls false [.cw], adv s)
    | some 's' => some (.cls false [.cs], adv s)
    | some 'D' => some (.cls false [.cnd], adv s)
    | some 'W' => some (.cls false [.cnw], adv s)
    | some 'S' => some (.cls false [.cns], adv s)
    | some 'b' => some (.wordb, adv s)
    | some 'B' => some (.nwordb, adv s)
    | some 'n' => some (.char '\n', adv s)
    | some 't' => some (.char '\t', adv s)
    | some 'r' => some (.char '\r', adv s)
    | some c => some (.char c, adv s)
    | none => some (.char '\\', s)
  | some c => some (.char c, adv s0)

end

def parse (pat : String) : Re :=
  (parseAlt { pat := pat.toList.toArray, pos := 0 }).1

-- ----- matcher (backtracking, CPS) -----

def isWord (c : Char) : Bool :=
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'

def citemMatch (it : CItem) (c : Char) : Bool :=
  match it with
  | .cchar x => c == x
  | .crange a b => c >= a && c <= b
  | .cd => c >= '0' && c <= '9'
  | .cnd => !(c >= '0' && c <= '9')
  | .cw => isWord c
  | .cnw => !isWord c
  | .cs => c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\x0c' || c == '\x0b'
  | .cns => !(c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\x0c' || c == '\x0b')

/- The continuation returns the accepting end position (or none); the first
   accepting continuation under backtracking order wins, exactly like the
   bool-CPS matcher in the OCaml port (`Option.orElse` plays the role of `||`). -/
mutual

partial def mNode (input : Array Char) (len : Nat) (node : Node) (pos : Nat)
    (k : Nat → Option Nat) : Option Nat :=
  match node with
  | .char c => if pos < len && input[pos]! == c then k (pos + 1) else none
  | .any => if pos < len && input[pos]! != '\n' then k (pos + 1) else none
  | .start => if pos == 0 then k pos else none
  | .stop => if pos == len then k pos else none
  | .wordb =>
    let before := pos > 0 && isWord input[pos - 1]!
    let after := pos < len && isWord input[pos]!
    if before != after then k pos else none
  | .nwordb =>
    let before := pos > 0 && isWord input[pos - 1]!
    let after := pos < len && isWord input[pos]!
    if before == after then k pos else none
  | .cls neg items =>
    if pos < len then
      let c := input[pos]!
      let hit := items.any (citemMatch · c)
      if (if neg then !hit else hit) then k (pos + 1) else none
    else none
  | .grp alts => alts.firstM (fun seq => mSeq input len seq pos k)
  | .opt greedy a =>
    if greedy then (mNode input len a pos k).orElse (fun _ => k pos)
    else (k pos).orElse (fun _ => mNode input len a pos k)
  | .star greedy a => mStar input len greedy a pos k
  | .plus greedy a =>
    mNode input len a pos (fun p => mStar input len greedy a p k)
  | .rep greedy mn mx a => mRep input len greedy mn mx a pos k

partial def mStar (input : Array Char) (len : Nat) (greedy : Bool) (a : Node) (pos : Nat)
    (k : Nat → Option Nat) : Option Nat :=
  let more := fun (p : Nat) =>
    if p > pos then mStar input len greedy a p k else none
  if greedy then (mNode input len a pos more).orElse (fun _ => k pos)
  else (k pos).orElse (fun _ => mNode input len a pos more)

partial def mRep (input : Array Char) (len : Nat) (greedy : Bool) (mn : Nat) (mx : Option Int)
    (a : Node) (pos : Nat) (k : Nat → Option Nat) : Option Nat :=
  if mn > 0 then
    mNode input len a pos (fun p =>
      mRep input len greedy (mn - 1) (mx.map (· - 1)) a p k)
  else
    match mx with
    | some 0 => k pos
    | _ =>
      let next := fun (p : Nat) =>
        if p > pos then mRep input len greedy 0 (mx.map (· - 1)) a p k else none
      if greedy then (mNode input len a pos next).orElse (fun _ => k pos)
      else (k pos).orElse (fun _ => mNode input len a pos next)

partial def mSeq (input : Array Char) (len : Nat) (seq : List Node) (pos : Nat)
    (k : Nat → Option Nat) : Option Nat :=
  match seq with
  | [] => k pos
  | x :: rest => mNode input len x pos (fun p => mSeq input len rest p k)

end

def compile (pat : String) : Re := parse pat

/- Does the pattern match anywhere in input? -/
partial def test (re : Re) (input : String) : Bool :=
  let chars := input.toList.toArray
  let len := chars.size
  let rec tryAt (i : Nat) : Bool :=
    if (re.firstM (fun seq => mSeq chars len seq i some)).isSome then true
    else if i >= len then false
    else tryAt (i + 1)
  tryAt 0

def testStr (pat : String) (input : String) : Bool := test (compile pat) input

/- Leftmost match: returns (start, stop) or none. Used by the public re_* API.
   Positions are character (codepoint) indices. -/
partial def findBounds (re : Re) (input : String) : Option (Nat × Nat) :=
  let chars := input.toList.toArray
  let len := chars.size
  let rec tryAt (i : Nat) : Option (Nat × Nat) :=
    if i > len then none
    else
      match re.firstM (fun seq => mSeq chars len seq i some) with
      | some e => some (i, e)
      | none => tryAt (i + 1)
  tryAt 0

end Vregex
