/- Minimal backtracking regex engine for the Lean port of voxgig/struct.
   Supports the RE2 subset the corpus exercises: literals, '.', anchors ^ $,
   \b and \B, character classes [..] / [^..] with ranges and \d \w \s \D \W \S,
   groups (..), (?:..) and (?P<name>..), alternation |, quantifiers * + ? and
   {n}/{n,}/{n,m} with optional lazy '?'. Capturing groups are tracked, so
   the engine backs the full re_* API (find with captures, find_all, replace)
   at the Go-stdlib minimum bar; `test` also serves $LIKE. No third-party
   dependency. -/

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
  | grp (gi : Nat) (alts : List (List Node))  -- alternation; gi>0 = capture index
  | star (greedy : Bool) (atom : Node)
  | plus (greedy : Bool) (atom : Node)
  | opt (greedy : Bool) (atom : Node)
  | rep (greedy : Bool) (mn : Nat) (mx : Option Int) (atom : Node)
  deriving Repr

/- Compiled = the alternation AST plus the number of capturing groups. -/
structure Re where
  alts : List (List Node)
  ngroups : Nat

-- ----- parser (over an Array Char) -----

private structure PState where
  pat : Array Char
  pos : Nat
  gc : Nat := 0                        -- capturing groups seen so far

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
    -- (?: is non-capturing; a plain ( and an RE2 named group (?P<name> are
    -- both capturing (names are not tracked). Indices follow opening parens.
    let (gi, s) :=
      if peekAt s == some '?' && peekAt s 1 == some ':' then (0, adv (adv s))
      else if peekAt s == some '?' && peekAt s 1 == some 'P' && peekAt s 2 == some '<' then
        Id.run do
          let mut t := adv (adv (adv s))
          while peekAt t != none && peekAt t != some '>' do
            t := adv t
          if peekAt t == some '>' then t := adv t
          return (t.gc + 1, { t with gc := t.gc + 1 })
      else (s.gc + 1, { s with gc := s.gc + 1 })
    let (alts, s) := parseAlt s
    let s := if peekAt s == some ')' then adv s else s
    some (.grp gi alts, s)
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
  let (alts, st) := parseAlt { pat := pat.toList.toArray, pos := 0 }
  { alts, ngroups := st.gc }

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

/- The continuation receives the accepting end position and the capture
   spans so far (or fails with none); the first accepting continuation under
   backtracking order wins. Capture spans are threaded functionally, so
   backtracking naturally discards abandoned group records. -/

/-- Capture spans, one slot per capturing group (1-based groups at index-1). -/
abbrev Caps := Array (Option (Nat × Nat))

abbrev K := Nat → Caps → Option (Nat × Caps)

mutual

partial def mNode (input : Array Char) (len : Nat) (node : Node) (pos : Nat)
    (caps : Caps) (k : K) : Option (Nat × Caps) :=
  match node with
  | .char c => if pos < len && input[pos]! == c then k (pos + 1) caps else none
  | .any => if pos < len && input[pos]! != '\n' then k (pos + 1) caps else none
  | .start => if pos == 0 then k pos caps else none
  | .stop => if pos == len then k pos caps else none
  | .wordb =>
    let before := pos > 0 && isWord input[pos - 1]!
    let after := pos < len && isWord input[pos]!
    if before != after then k pos caps else none
  | .nwordb =>
    let before := pos > 0 && isWord input[pos - 1]!
    let after := pos < len && isWord input[pos]!
    if before == after then k pos caps else none
  | .cls neg items =>
    if pos < len then
      let c := input[pos]!
      let hit := items.any (citemMatch · c)
      if (if neg then !hit else hit) then k (pos + 1) caps else none
    else none
  | .grp gi alts =>
    let k' : K :=
      if gi == 0 then k
      else fun p caps' => k p (caps'.set! (gi - 1) (some (pos, p)))
    alts.firstM (fun seq => mSeq input len seq pos caps k')
  | .opt greedy a =>
    if greedy then (mNode input len a pos caps k).orElse (fun _ => k pos caps)
    else (k pos caps).orElse (fun _ => mNode input len a pos caps k)
  | .star greedy a => mStar input len greedy a pos caps k
  | .plus greedy a =>
    mNode input len a pos caps (fun p caps' => mStar input len greedy a p caps' k)
  | .rep greedy mn mx a => mRep input len greedy mn mx a pos caps k

partial def mStar (input : Array Char) (len : Nat) (greedy : Bool) (a : Node) (pos : Nat)
    (caps : Caps) (k : K) : Option (Nat × Caps) :=
  let more : K := fun p caps' =>
    if p > pos then mStar input len greedy a p caps' k else none
  if greedy then (mNode input len a pos caps more).orElse (fun _ => k pos caps)
  else (k pos caps).orElse (fun _ => mNode input len a pos caps more)

partial def mRep (input : Array Char) (len : Nat) (greedy : Bool) (mn : Nat) (mx : Option Int)
    (a : Node) (pos : Nat) (caps : Caps) (k : K) : Option (Nat × Caps) :=
  if mn > 0 then
    mNode input len a pos caps (fun p caps' =>
      mRep input len greedy (mn - 1) (mx.map (· - 1)) a p caps' k)
  else
    match mx with
    | some 0 => k pos caps
    | _ =>
      let next : K := fun p caps' =>
        if p > pos then mRep input len greedy 0 (mx.map (· - 1)) a p caps' k else none
      if greedy then (mNode input len a pos caps next).orElse (fun _ => k pos caps)
      else (k pos caps).orElse (fun _ => mNode input len a pos caps next)

partial def mSeq (input : Array Char) (len : Nat) (seq : List Node) (pos : Nat)
    (caps : Caps) (k : K) : Option (Nat × Caps) :=
  match seq with
  | [] => k pos caps
  | x :: rest => mNode input len x pos caps (fun p caps' => mSeq input len rest p caps' k)

end

def compile (pat : String) : Re := parse pat

/-- First match at or after position `i`: `(mstart, mend, caps)`. -/
partial def findAt (re : Re) (chars : Array Char) (len : Nat) (i : Nat) :
    Option (Nat × Nat × Caps) :=
  let rec tryAt (i : Nat) : Option (Nat × Nat × Caps) :=
    if i > len then none
    else
      let caps0 : Caps := Array.replicate re.ngroups none
      match re.alts.firstM (fun seq => mSeq chars len seq i caps0 (fun p c => some (p, c))) with
      | some (e, caps) => some (i, e, caps)
      | none => tryAt (i + 1)
  tryAt i

/- Does the pattern match anywhere in input? -/
partial def test (re : Re) (input : String) : Bool :=
  let chars := input.toList.toArray
  (findAt re chars chars.size 0).isSome

def testStr (pat : String) (input : String) : Bool := test (compile pat) input

/-- Leftmost match bounds `(start, stop)` in character (codepoint) indices. -/
partial def findBounds (re : Re) (input : String) : Option (Nat × Nat) :=
  let chars := input.toList.toArray
  (findAt re chars chars.size 0).map (fun (s, e, _) => (s, e))

private def sub (chars : Array Char) (a b : Nat) : String :=
  String.ofList (chars.extract a b).toList

/-- First match as `[whole, capture1, ...]`; unmatched groups are `""`. -/
partial def find (re : Re) (input : String) : Option (List String) :=
  let chars := input.toList.toArray
  (findAt re chars chars.size 0).map fun (ms, me, caps) =>
    sub chars ms me :: (caps.toList.map (fun c =>
      match c with
      | some (a, b) => sub chars a b
      | none => ""))

/-- Every non-overlapping match, left to right (Go FindAllStringSubmatch). -/
partial def findAll (re : Re) (input : String) : List (List String) := Id.run do
  let chars := input.toList.toArray
  let len := chars.size
  let mut out : List (List String) := []
  let mut pos := 0
  repeat do
    match findAt re chars len pos with
    | none => break
    | some (ms, me, caps) =>
      out := (sub chars ms me :: (caps.toList.map (fun c =>
        match c with
        | some (a, b) => sub chars a b
        | none => ""))) :: out
      pos := if me == ms then me + 1 else me
      if pos > len then break
  return out.reverse

/-- Replace every match; the template supports `$&` (whole), `$1`..`$9` and
    `$$` (a literal `$`). On a zero-width match the current character is
    emitted and the scan advances one position. -/
partial def replaceAll (re : Re) (input : String) (template : String) : String := Id.run do
  let chars := input.toList.toArray
  let len := chars.size
  let tmpl := template.toList.toArray
  let mut out := ""
  let mut pos := 0
  repeat do
    match findAt re chars len pos with
    | none =>
      out := out ++ sub chars pos len
      break
    | some (ms, me, caps) =>
      out := out ++ sub chars pos ms
      let mut ti := 0
      while ti < tmpl.size do
        let ch := tmpl[ti]!
        if ch == '$' && ti + 1 < tmpl.size then
          let nc := tmpl[ti + 1]!
          if nc == '$' then
            out := out.push '$'
            ti := ti + 2
          else if nc == '&' || (nc >= '0' && nc <= '9') then
            if nc == '&' || nc == '0' then
              out := out ++ sub chars ms me
            else
              let gi := nc.toNat - '0'.toNat
              if gi <= re.ngroups then
                match caps[gi - 1]! with
                | some (a, b) => out := out ++ sub chars a b
                | none => pure ()
            ti := ti + 2
          else
            out := out.push ch
            ti := ti + 1
        else
          out := out.push ch
          ti := ti + 1
      if me == ms then
        if ms < len then
          out := out.push chars[ms]!
        pos := ms + 1
        if pos > len then break
      else
        pos := me
  return out

end Vregex
