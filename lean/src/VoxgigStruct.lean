/- Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.

   Voxgig Struct — Lean 4 port.

   A faithful port of the canonical TypeScript implementation
   (typescript/src/StructUtility.ts), following the OCaml port's structure.
   Like TypeScript (and the OCaml, Rust and Haskell ports), Lean keeps
   `undefined` (noval) and JSON `null` (null) distinct, so this port mirrors
   the canonical TS logic directly.

   Nodes are mutable and reference-stable: because Lean's strict positivity
   rules forbid `IO.Ref` fields inside the `Value` inductive, lists and maps
   are handles (indices) into a global mutable heap (the same design as the
   Elixir port's ETS heap). Function values are likewise handles into a
   registry, and the mutable `Injection` state lives in its own arena. The
   whole API therefore runs in `IO` (as in the Haskell port). Zero
   third-party runtime dependencies; the regex helper is the in-tree Vregex
   engine (RE2 subset). -/

import Vregex

namespace VoxgigStruct

-- ---------------------------------------------------------------------------
-- Value model
-- ---------------------------------------------------------------------------

/-- A JSON-shaped dynamic value. `noval` is TS `undefined` (property absent);
    `null` is JSON null. `list`/`map` are handles into the global node heap;
    `func` is a handle into the injector registry. -/
inductive Value where
  | noval
  | null
  | bool (b : Bool)
  | num (n : Float)
  | str (s : String)
  | list (id : Nat)
  | map (id : Nat)
  | func (fid : Nat)
  | sentinel (tag : String)      -- SKIP / DELETE, by tag
  deriving Repr

instance : Inhabited Value := ⟨.noval⟩

instance : BEq Value where
  beq a b :=
    match a, b with
    | .noval, .noval => true
    | .null, .null => true
    | .bool x, .bool y => x == y
    | .num x, .num y => x == y
    | .str x, .str y => x == y
    | .list x, .list y => x == y
    | .map x, .map y => x == y
    | .func x, .func y => x == y
    | .sentinel x, .sentinel y => x == y
    | _, _ => false

/-- A heap slot: the payload of one list or map node. -/
inductive Slot where
  | slist (items : Array Value)
  | smap (entries : Array (String × Value))
  deriving Inhabited

/-- Injection state handle (index into the injection arena). -/
abbrev InjId := Nat

/-- The mutable `Injection` record (canonical TS `Injection`). Mutation goes
    through the arena (`modInj`), so child injections can share and update
    ancestor state exactly as the canonical algorithm requires. -/
structure InjData where
  mode : Nat := 4
  full : Bool := false
  keyi : Int := 0
  keys : Value := .noval           -- List of Str
  key : Value := .noval            -- Str
  ival : Value := .noval
  parent : Value := .noval
  path : Value := .noval           -- List of Str
  nodes : Value := .noval          -- List
  handler : Nat := 0               -- injector registry id
  errs : Value := .noval           -- List
  imeta : Value := .noval          -- Map ("meta" is a Lean keyword)
  dparent : Value := .noval
  dpath : Value := .noval          -- List
  base : Value := .noval           -- Str or noval
  modify : Option Nat := none      -- modify registry id
  prior : Option InjId := none
  extra : Value := .noval
  deriving Inhabited


/-- injdef: the loose `Partial<Injection>` the public API accepts. -/
structure InjDef where
  dMeta : Value := .noval
  dExtra : Value := .noval
  dErrs : Value := .noval
  dModify : Option Nat := none     -- modify registry id
  dHandler : Option Nat := none    -- injector registry id
  dBase : Value := .noval
  dDparent : Value := .noval
  dDpath : Value := .noval
  dKey : Value := .noval
  deriving Inhabited

inductive InjArg where
  | iinj (i : InjId)
  | idef (d : InjDef)
  | inone

/-- All mutable state of one library instance: the node heap, the function
    registries and the injection arena.

    This is threaded through every operation via `SIO` (a `ReaderT`) rather
    than stored in module-`initialize` globals: values stored in a persistent
    global `IO.Ref` are marked as shared by the Lean runtime, which defeats
    functional-but-in-place array updates and would make every heap write
    O(heap). Runtime-created refs stay unshared and update in place.

    Registered injector/modify functions are stored as plain `IO` closures
    with the ctx captured at registration time, so the structure is not
    recursive. -/
structure Ctx where
  valueHeap : IO.Ref (Array Slot)
  funcReg : IO.Ref (Array (InjId → Value → String → Value → IO Value))
  modifyReg : IO.Ref (Array (Value → Value → Value → InjId → IO Unit))
  injHeap : IO.Ref (Array InjData)
  dummyInj : IO.Ref (Option InjId)
  injectHandlerFid : IO.Ref Nat

end VoxgigStruct

/-- The library monad: `IO` plus the `Ctx` state handle. -/
abbrev VoxgigStruct.SIO := ReaderT VoxgigStruct.Ctx IO

namespace VoxgigStruct

/-- The signature of injector functions (transform commands, validators,
    custom handlers): `inj → val → ref → store → result`. -/
abbrev InjectorFn := InjId → Value → String → Value → SIO Value

/-- The signature of `modify` callbacks: `val → key → parent → inj`. -/
abbrev ModifyFn := Value → Value → Value → InjId → SIO Unit


-- ---------------------------------------------------------------------------
-- Heap / arena / registry primitives
-- ---------------------------------------------------------------------------

def newList (xs : Array Value) : SIO Value := do
  (← read).valueHeap.modifyGet fun h => (Value.list h.size, h.push (.slist xs))

def newMap (es : Array (String × Value)) : SIO Value := do
  (← read).valueHeap.modifyGet fun h => (Value.map h.size, h.push (.smap es))

def emptyList : SIO Value := newList #[]
def emptyMap : SIO Value := newMap #[]

def listItems (id : Nat) : SIO (Array Value) := do
  match (← (← read).valueHeap.get)[id]? with
  | some (.slist xs) => pure xs
  | _ => pure #[]

def setListItems (id : Nat) (xs : Array Value) : SIO Unit := do
  (← read).valueHeap.modify (·.set! id (.slist xs))

def mapEntries (id : Nat) : SIO (Array (String × Value)) := do
  match (← (← read).valueHeap.get)[id]? with
  | some (.smap es) => pure es
  | _ => pure #[]

def setMapEntries (id : Nat) (es : Array (String × Value)) : SIO Unit := do
  (← read).valueHeap.modify (·.set! id (.smap es))

def listItemsOf (v : Value) : SIO (Array Value) := do
  match v with
  | .list id => listItems id
  | _ => pure #[]

def mapEntriesOf (v : Value) : SIO (Array (String × Value)) := do
  match v with
  | .map id => mapEntries id
  | _ => pure #[]

-- ----- ordered map ops (insertion order preserved) -----

def omapGet (es : Array (String × Value)) (k : String) : Option Value :=
  (es.find? (·.1 == k)).map (·.2)

def omapHas (es : Array (String × Value)) (k : String) : Bool :=
  es.any (·.1 == k)

def omapSet (es : Array (String × Value)) (k : String) (v : Value) :
    Array (String × Value) :=
  if omapHas es k then es.map (fun (k', v') => if k' == k then (k, v) else (k', v'))
  else es.push (k, v)

def omapDel (es : Array (String × Value)) (k : String) : Array (String × Value) :=
  es.filter (·.1 != k)

def mapSetKV (id : Nat) (k : String) (v : Value) : SIO Unit := do
  setMapEntries id (omapSet (← mapEntries id) k v)

def mapDelK (id : Nat) (k : String) : SIO Unit := do
  setMapEntries id (omapDel (← mapEntries id) k)

-- ----- injection arena -----

def newInjData (d : InjData) : SIO InjId := do
  (← read).injHeap.modifyGet fun a => (a.size, a.push d)

def getInj (i : InjId) : SIO InjData := do
  pure (((← (← read).injHeap.get)[i]?).getD default)

def modInj (i : InjId) (f : InjData → InjData) : SIO Unit := do
  (← read).injHeap.modify fun a => a.modify i f

def getDummyInj : SIO InjId := do
  pure ((← (← read).dummyInj.get).getD 0)

-- ----- function / modify registries -----

def registerFunc (f : InjectorFn) : SIO Nat := do
  let ctx ← read
  ctx.funcReg.modifyGet fun a =>
    (a.size, a.push (fun i v r st => (f i v r st).run ctx))

def vFunc (f : InjectorFn) : SIO Value := do
  pure (.func (← registerFunc f))

def callFunc (fid : Nat) (inj : InjId) (v : Value) (ref : String) (store : Value) :
    SIO Value := do
  match (← (← read).funcReg.get)[fid]? with
  | some f => f inj v ref store
  | none => pure .noval

def registerModify (f : ModifyFn) : SIO Nat := do
  let ctx ← read
  ctx.modifyReg.modifyGet fun a =>
    (a.size, a.push (fun v k p i => (f v k p i).run ctx))

def callModify (mid : Nat) (v key parent : Value) (inj : InjId) : SIO Unit := do
  match (← (← read).modifyReg.get)[mid]? with
  | some f => f v key parent inj
  | none => pure ()

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

def M_KEYPRE : Nat := 1
def M_KEYPOST : Nat := 2
def M_VAL : Nat := 4
def MODENAME : List String := ["key:pre", "key:post", "val"]

def S_DKEY : String := "$KEY"
def S_BANNO : String := "`$ANNO`"
def S_DTOP : String := "$TOP"
def S_DERRS : String := "$ERRS"
def S_DSPEC : String := "$SPEC"
def S_BEXACT : String := "`$EXACT`"
def S_BVAL : String := "`$VAL`"
def S_BKEY : String := "`$KEY`"
def S_BOPEN : String := "`$OPEN`"

def S_MT : String := ""
def S_BT : String := "`"
def S_DS : String := "$"
def S_DT : String := "."
def S_CN : String := ":"
def S_FS : String := "/"
def S_KEY : String := "KEY"
def S_VIZ : String := ": "

def S_STRING : String := "string"
def S_OBJECT : String := "object"
def S_LIST : String := "list"
def S_MAP : String := "map"
def S_NIL : String := "nil"
def S_NULL : String := "null"

def T_ANY : Nat := 2 ^ 31 - 1
def T_NOVAL : Nat := 2 ^ 30
def T_BOOLEAN : Nat := 2 ^ 29
def T_DECIMAL : Nat := 2 ^ 28
def T_INTEGER : Nat := 2 ^ 27
def T_NUMBER : Nat := 2 ^ 26
def T_STRING : Nat := 2 ^ 25
def T_FUNCTION : Nat := 2 ^ 24
def T_SYMBOL : Nat := 2 ^ 23
def T_NULL : Nat := 2 ^ 22
def T_LIST : Nat := 2 ^ 14
def T_MAP : Nat := 2 ^ 13
def T_INSTANCE : Nat := 2 ^ 12
def T_SCALAR : Nat := 2 ^ 7
def T_NODE : Nat := 2 ^ 6

def typenameTbl : Array String := #[
  "any", "nil", "boolean", "decimal", "integer", "number", "string", "function",
  "symbol", "null", "", "", "", "", "", "", "", "list", "map", "instance",
  "", "", "", "", "scalar", "node"]

def SKIP : Value := .sentinel "skip"
def DELETE : Value := .sentinel "delete"

def MAXDEPTH : Int := 32

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

def isNoval : Value → Bool
  | .noval => true
  | _ => false

def isNullish : Value → Bool
  | .noval | .null => true
  | _ => false

def isSkip (v : Value) : Bool :=
  match v with
  | .sentinel "skip" => true
  | _ => false

def isDelete (v : Value) : Bool :=
  match v with
  | .sentinel "delete" => true
  | _ => false

def isIntegerF (n : Float) : Bool :=
  n.isFinite && n.floor == n

/-- Truncate-toward-zero conversion (OCaml `int_of_float`). -/
def fToInt (f : Float) : Int :=
  f.toInt64.toInt

def intToFloat (i : Int) : Float := Float.ofInt i

def vInt (i : Int) : Value := .num (intToFloat i)

def strLtB (a b : String) : Bool := decide (a < b)

def strContains (s : String) (c : Char) : Bool := s.contains c

/-- Character-indexed substring `[a, b)`. -/
def strSub (s : String) (a b : Nat) : String :=
  String.ofList ((s.toList.toArray.extract a b).toList)

def zerosStr (n : Nat) : String := String.ofList (List.replicate n '0')

def strTake (s : String) (n : Nat) : String := String.ofList (s.toList.take n)
def strDrop (s : String) (n : Nat) : String := String.ofList (s.toList.drop n)

def hexDigits : Array Char :=
  #['0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f']

def toHex (n : Nat) (width : Nat) (upper : Bool := false) : String := Id.run do
  let mut digits : List Char := []
  let mut x := n
  while x > 0 do
    let d := hexDigits[x % 16]!
    digits := (if upper then d.toUpper else d) :: digits
    x := x / 16
  while digits.length < width do
    digits := '0' :: digits
  return String.ofList digits

/-- Strict integer string parse: optional leading `-`, then decimal digits. -/
def strToInt? (s : String) : Option Int := Id.run do
  let cs := s.toList.toArray
  if cs.size == 0 then return none
  let neg := cs[0]! == '-'
  let start := if neg then 1 else 0
  if cs.size ≤ start then return none
  let mut n : Nat := 0
  for i in [start:cs.size] do
    let c := cs[i]!
    if c >= '0' && c <= '9' then
      n := n * 10 + (c.toNat - '0'.toNat)
    else
      return none
  return some (if neg then -(n : Int) else (n : Int))

/-- OCaml `is_int_key`: nonempty and every char is a digit or `-`. -/
def isIntKey (s : String) : Bool :=
  s.length > 0 && s.toList.all (fun c => (c >= '0' && c <= '9') || c == '-')

-- ----- JS number formatting (shortest round-trip, ECMA Number::toString) -----

/-- Shortest round-trip decimal digits of a positive finite float. Returns
    `(digits, n10)` where the value is `0.digits × 10^n10`. Exact `Nat`
    arithmetic on the float's binary mantissa/exponent; candidates are
    validated by re-parsing with `Float.ofScientific` (the same primitive the
    JSON reader uses, so printing and parsing agree). -/
def shortestDigits (a : Float) : String × Int := Id.run do
  let (fr, ex) := a.frExp
  let m : Nat := ((fr * (2.0 ^ (53 : Nat).toFloat)).toUInt64).toNat
  let e2 : Int := ex - 53
  let (nN, dD) : Nat × Nat :=
    if e2 >= 0 then (m <<< e2.toNat, 1) else (m, 1 <<< (-e2).toNat)
  -- t: smallest exponent with value < 10^t (so 10^(t-1) ≤ value < 10^t)
  let cond : Int → Bool := fun t =>
    if t >= 0 then nN < dD * 10 ^ t.toNat
    else nN * 10 ^ (-t).toNat < dD
  let mut t : Int := (ex * 30103) / 100000
  while !(cond t) do t := t + 1
  while cond (t - 1) do t := t - 1
  let mut result : String × Int := ("", 0)
  let mut found := false
  for p in [1:18] do
    if !found then
      let scale : Int := (p : Int) - t
      let num := nN * 10 ^ (max 0 scale).toNat
      let den := dD * 10 ^ (max 0 (-scale)).toNat
      let q0 := (2 * num + den) / (2 * den)
      let (q, tt) := if q0 == 10 ^ p then (10 ^ (p - 1), t + 1) else (q0, t)
      let e10 : Int := tt - (p : Int)
      let f := if e10 < 0 then Float.ofScientific q true (-e10).toNat
               else Float.ofScientific q false e10.toNat
      if f == a || p == 17 then
        let mut qq := q
        while qq > 0 && qq % 10 == 0 do qq := qq / 10
        result := (toString qq, tt)
        found := true
  return result

/-- ECMA-262 Number::toString(10) layout from shortest digits. -/
def formatDecimal (neg : Bool) (s : String) (n10 : Int) : String :=
  let k : Int := s.length
  let core :=
    if k <= n10 && n10 <= 21 then s ++ zerosStr (n10 - k).toNat
    else if 0 < n10 && n10 <= 21 then strTake s n10.toNat ++ "." ++ strDrop s n10.toNat
    else if -6 < n10 && n10 <= 0 then "0." ++ zerosStr (-n10).toNat ++ s
    else
      let mant := if k == 1 then s else strTake s 1 ++ "." ++ strDrop s 1
      let e := n10 - 1
      mant ++ "e" ++ (if e >= 0 then "+" ++ toString e else toString e)
  if neg then "-" ++ core else core

/-- JS `String(n)` for numbers. -/
def numToString (n : Float) : String :=
  if n.isNaN then "NaN"
  else if n == 0.0 then "0"
  else if n.isInf then (if n < 0.0 then "-Infinity" else "Infinity")
  else
    let neg := n < 0.0
    let a := if neg then -n else n
    if isIntegerF n && a < 1e16 then
      (if neg then "-" else "") ++ toString a.toUInt64
    else
      let (s, e10) := shortestDigits a
      formatDecimal neg s e10

/-- Simple decimal float parse (OCaml `float_of_string` for the corpus needs);
    `none` when the string is not a plain decimal number. -/
def parseFloatJS (s : String) : Option Float := Id.run do
  let cs := s.toList.toArray
  let n := cs.size
  if n == 0 then return none
  let mut i := 0
  let mut neg := false
  if cs[0]! == '-' then neg := true; i := 1
  else if cs[0]! == '+' then i := 1
  let mut mant : Nat := 0
  let mut digits := 0
  while i < n && cs[i]! >= '0' && cs[i]! <= '9' do
    mant := mant * 10 + (cs[i]!.toNat - '0'.toNat)
    digits := digits + 1
    i := i + 1
  let mut fracLen : Nat := 0
  if i < n && cs[i]! == '.' then
    i := i + 1
    while i < n && cs[i]! >= '0' && cs[i]! <= '9' do
      mant := mant * 10 + (cs[i]!.toNat - '0'.toNat)
      fracLen := fracLen + 1
      digits := digits + 1
      i := i + 1
  if digits == 0 then return none
  let mut exp10 : Int := -(fracLen : Int)
  if i < n && (cs[i]! == 'e' || cs[i]! == 'E') then
    i := i + 1
    let mut eneg := false
    if i < n && (cs[i]! == '-' || cs[i]! == '+') then
      eneg := cs[i]! == '-'
      i := i + 1
    let mut e : Nat := 0
    let mut edigits := 0
    while i < n && cs[i]! >= '0' && cs[i]! <= '9' do
      e := e * 10 + (cs[i]!.toNat - '0'.toNat)
      edigits := edigits + 1
      i := i + 1
    if edigits == 0 then return none
    exp10 := exp10 + (if eneg then -(e : Int) else (e : Int))
  if i != n then return none
  let a := if exp10 < 0 then Float.ofScientific mant true (-exp10).toNat
           else Float.ofScientific mant false exp10.toNat
  return some (if neg then -a else a)

def clz32 (t : Int) : Nat :=
  let n : Nat := ((t % (2 ^ 32 : Int) + 2 ^ 32) % 2 ^ 32).toNat
  if n == 0 then 32 else 31 - Nat.log2 n

-- ---------------------------------------------------------------------------
-- Minor utilities
-- ---------------------------------------------------------------------------

def isnode (v : Value) : Bool :=
  match v with
  | .map _ | .list _ => true
  | _ => false

def ismap (v : Value) : Bool :=
  match v with
  | .map _ => true
  | _ => false

def islist (v : Value) : Bool :=
  match v with
  | .list _ => true
  | _ => false

def isfunc (v : Value) : Bool :=
  match v with
  | .func _ => true
  | _ => false

def iskey (k : Value) : Bool :=
  match k with
  | .str s => s != ""
  | .num _ => true
  | _ => false

def isempty (v : Value) : SIO Bool := do
  if isNullish v then return true
  if v == .str "" then return true
  match v with
  | .list id => return (← listItems id).isEmpty
  | .map id => return (← mapEntries id).isEmpty
  | _ => return false

def getdef (v alt : Value) : Value :=
  if isNoval v then alt else v

def typify (v : Value) : Nat :=
  match v with
  | .noval => T_NOVAL
  | .null => T_SCALAR ||| T_NULL
  | .bool _ => T_SCALAR ||| T_BOOLEAN
  | .num n =>
    if n.isNaN then T_NOVAL
    else if isIntegerF n then T_SCALAR ||| T_NUMBER ||| T_INTEGER
    else T_SCALAR ||| T_NUMBER ||| T_DECIMAL
  | .str _ => T_SCALAR ||| T_STRING
  | .func _ => T_SCALAR ||| T_FUNCTION
  | .list _ => T_NODE ||| T_LIST
  | .map _ => T_NODE ||| T_MAP
  | .sentinel _ => T_NODE ||| T_MAP

def typename (t : Int) : String :=
  let i := clz32 t
  if i < typenameTbl.size then typenameTbl[i]! else typenameTbl[0]!

def size (v : Value) : SIO Int := do
  match v with
  | .list id => return ((← listItems id).size : Int)
  | .map id => return ((← mapEntries id).size : Int)
  | .str s => return (s.length : Int)
  | .bool b => return (if b then 1 else 0)
  | .num n => return fToInt n.floor
  | _ => return 0

def strkey (key : Value := .noval) : String :=
  match key with
  | .noval => S_MT
  | .str s => s
  | .bool _ => S_MT
  | .num n => if isIntegerF n then numToString n else numToString n.floor
  | _ => S_MT

def keysof (v : Value) : SIO (Array String) := do
  match v with
  | .map id =>
    return ((← mapEntries id).map (·.1)).qsort strLtB
  | .list id =>
    let xs ← listItems id
    return (Array.range xs.size).map (fun i => toString i)
  | _ => return #[]

/-- JS `'' + v` / `String(v)` for keys and concatenation. -/
partial def jsString (v : Value) : SIO String := do
  match v with
  | .noval => pure "undefined"
  | .null => pure "null"
  | .bool b => pure (if b then "true" else "false")
  | .num n => pure (numToString n)
  | .str s => pure s
  | .list id => do
    let xs ← listItems id
    let mut parts : List String := []
    for x in xs do
      let p ← match x with
        | .noval | .null => pure ""
        | _ => jsString x
      parts := p :: parts
    pure (String.intercalate "," parts.reverse)
  | .map _ => pure "[object Object]"
  | .func _ => pure "function"
  | .sentinel s => pure s

/-- internal: list element by numeric key, no negative wrap, noval if oob. -/
def listIndex (id : Nat) (key : Value) : SIO Value := do
  let ks := match key with
    | .str s => s
    | .num n => numToString n
    | _ => ""
  match strToInt? ks with
  | some i =>
    if i >= 0 then
      let xs ← listItems id
      if i < (xs.size : Int) then return xs[i.toNat]! else return .noval
    else return .noval
  | none => return .noval

partial def getprop (v key : Value) (alt : Value := .noval) : SIO Value := do
  if isNoval v || isNoval key then return alt
  let out ←
    match v with
    | .map id => do
      pure ((omapGet (← mapEntries id) (← jsString key)).getD .noval)
    | .list id => listIndex id key
    | _ => pure .noval
  if isNullish out then return alt else return out

/-- Raw lookup preserving stored `null` (canonical TS bracket access). -/
partial def lookupRaw (v key : Value) : SIO Value := do
  if isNoval v || isNoval key then return .noval
  match v with
  | .map id => pure ((omapGet (← mapEntries id) (← jsString key)).getD .noval)
  | .list id => listIndex id key
  | _ => pure .noval

def haskey (v key : Value) : SIO Bool := do
  return !(isNullish (← getprop v key))

partial def getelem (v key : Value) (alt : Value := .noval) : SIO Value := do
  if isNoval v || isNoval key then return alt
  let out ←
    match v with
    | .list id => do
      let ks := match key with
        | .str s => s
        | .num n => numToString n
        | _ => ""
      if isIntKey ks then
        match strToInt? ks with
        | some nk0 => do
          let xs ← listItems id
          let len : Int := xs.size
          let nk := if nk0 < 0 then len + nk0 else nk0
          if nk >= 0 && nk < len then pure xs[nk.toNat]! else pure .noval
        | none => pure .noval
      else pure .noval
    | _ => pure .noval
  if isNullish out then
    match alt with
    | .func fid => callFunc fid (← getDummyInj) .noval "" .noval
    | _ => pure alt
  else pure out

/-- literal stored value at string key k, preserving null. -/
def getpropRaw (v : Value) (k : String) : SIO Value := do
  match v with
  | .map id => pure ((omapGet (← mapEntries id) k).getD .noval)
  | .list id =>
    match strToInt? k with
    | some i =>
      if i >= 0 then do
        let xs ← listItems id
        if i < (xs.size : Int) then pure xs[i.toNat]! else pure .noval
      else pure .noval
    | none => pure .noval
  | _ => pure .noval

def itemsPairs (v : Value) : SIO (Array (String × Value)) := do
  if !(isnode v) then return #[]
  let ks ← keysof v
  let mut out : Array (String × Value) := #[]
  for k in ks do
    out := out.push (k, ← getpropRaw v k)
  return out

def itemsV (v : Value) (f : (String × Value) → SIO Value) : SIO Value := do
  let ps ← itemsPairs v
  let mut out : Array Value := #[]
  for p in ps do
    out := out.push (← f p)
  newList out

def items (v : Value) : SIO Value := do
  let ps ← itemsPairs v
  let mut out : Array Value := #[]
  for (k, x) in ps do
    out := out.push (← newList #[.str k, x])
  newList out

partial def flatten (l : Value) (depth : Int := 1) : SIO Value := do
  if !(islist l) then return l
  let xs ← listItemsOf l
  let mut out : Array Value := #[]
  for item in xs do
    if islist item && depth > 0 then
      let f ← flatten item (depth - 1)
      for x in (← listItemsOf f) do
        out := out.push x
    else
      out := out.push item
  newList out

def filter (v : Value) (check : (String × Value) → Bool) : SIO Value := do
  let ps ← itemsPairs v
  let mut out : Array Value := #[]
  for (k, x) in ps do
    if check (k, x) then out := out.push x
  newList out

partial def setprop (parent key v : Value) : SIO Value := do
  if !(iskey key) then return parent
  match parent with
  | .map id => mapSetKV id (← jsString key) v
  | .list id => do
    let ks := match key with
      | .str s => s
      | .num n => numToString n.floor
      | _ => ""
    match strToInt? ks with
    | none => pure ()
    | some ki0 => do
      let xs ← listItems id
      let len : Int := xs.size
      if ki0 >= 0 then
        let ki := if ki0 > len then len else ki0
        if ki >= len then setListItems id (xs.push v)
        else setListItems id (xs.set! ki.toNat v)
      else
        setListItems id (#[v] ++ xs)
  | _ => pure ()
  return parent

partial def delprop (parent key : Value) : SIO Value := do
  if !(iskey key) then return parent
  match parent with
  | .map id => mapDelK id (← jsString key)
  | .list id => do
    let ks := match key with
      | .str s => s
      | .num n => numToString n.floor
      | _ => ""
    match strToInt? ks with
    | some ki =>
      if ki >= 0 then do
        let xs ← listItems id
        if ki < (xs.size : Int) then
          setListItems id ((xs.toList.eraseIdx ki.toNat).toArray)
    | none => pure ()
  | _ => pure ()
  return parent

partial def clone (v : Value) : SIO Value := do
  match v with
  | .list id => do
    let xs ← listItems id
    let mut out : Array Value := #[]
    for x in xs do
      out := out.push (← clone x)
    newList out
  | .map id => do
    let es ← mapEntries id
    let mut out : Array (String × Value) := #[]
    for (k, x) in es do
      out := out.push (k, ← clone x)
    newMap out
  | _ => pure v

partial def slice (v : Value) (start : Value := .noval) (stop : Value := .noval)
    (mutate : Bool := false) : SIO Value := do
  match v with
  | .num n =>
    let lo : Float := match start with | .num s => s | _ => -(1.0 / 0.0)
    let hi : Float := match stop with | .num e => e - 1.0 | _ => 1.0 / 0.0
    let x := if n < hi then n else hi
    return .num (if lo > x then lo else x)
  | .list _ | .str _ => do
    let vlen ← size v
    let start := match start with
      | .noval => if !(isNoval stop) then Value.num 0.0 else start
      | _ => start
    match start with
    | .num sf =>
      let s0 : Int := fToInt sf
      let (s1, e1) : Int × Int :=
        if s0 < 0 then (0, max 0 (vlen + s0))
        else match stop with
          | .num ef =>
            let e := fToInt ef
            if e < 0 then (s0, max 0 (vlen + e))
            else if vlen < e then (s0, vlen)
            else (s0, e)
          | _ => (s0, vlen)
      let s2 := if vlen < s1 then vlen else s1
      if s2 > -1 && s2 <= e1 && e1 <= vlen then
        match v with
        | .list id => do
          let xs ← listItems id
          let sub := xs.extract s2.toNat e1.toNat
          if mutate then do
            setListItems id sub
            return v
          else newList sub
        | .str str => return .str (strSub str s2.toNat e1.toNat)
        | _ => return v
      else
        match v with
        | .list id =>
          if mutate then do
            setListItems id #[]
            return v
          else emptyList
        | .str _ => return .str S_MT
        | _ => return v
    | _ => return v
  | _ => return v

-- ---------------------------------------------------------------------------
-- escre / escurl / regex helpers
-- ---------------------------------------------------------------------------

partial def escre (s : Value) : SIO Value := do
  let str ← match s with
    | .str x => pure x
    | .noval => pure S_MT
    | _ => jsString s
  let mut out := ""
  for c in str.toList do
    match c with
    | '.' | '*' | '+' | '?' | '^' | '$' | '{' | '}' | '(' | ')' | '|'
    | '[' | ']' | '\\' => out := out.push '\\' |>.push c
    | _ => out := out.push c
  return .str out

partial def escurl (s : Value) : SIO Value := do
  let str ← match s with
    | .str x => pure x
    | .noval => pure S_MT
    | _ => jsString s
  let bytes := str.toUTF8
  let mut out := ""
  for i in [0:bytes.size] do
    let b := bytes[i]!
    let c := Char.ofNat b.toNat
    let unreserved :=
      (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
      || c == '-' || c == '_' || c == '.' || c == '!' || c == '~' || c == '*'
      || c == '\'' || c == '(' || c == ')'
    if unreserved then out := out.push c
    else out := out ++ "%" ++ toHex b.toNat 2 (upper := true)
  return .str out

partial def reCompile (p : Value) (_flags : Value := .noval) : SIO Value := do
  match p with
  | .str _ => pure p
  | _ => pure (.str (← jsString p))

def reStr (p : Value) : SIO String := do
  match p with
  | .str s => pure s
  | _ => jsString p

partial def reFind (p input : Value) : SIO Value := do
  let ps ← reStr p
  let is ← reStr input
  match Vregex.findBounds (Vregex.compile ps) is with
  | some (s, e) => newList #[.str (strSub is s e)]
  | none => pure .null

partial def reFindAll (_p _input : Value) : SIO Value := emptyList

partial def reReplace (_p : Value) (input : Value) (_r : Value) : SIO Value := pure input

partial def reTest (p input : Value) : SIO Value := do
  return .bool (Vregex.testStr (← reStr p) (← reStr input))

partial def reEscape (s : Value) : SIO Value := escre s

-- ---------------------------------------------------------------------------
-- stringify / jsonify / pathify / join
-- ---------------------------------------------------------------------------

def jsonEscapeStr (s : String) : String := Id.run do
  let mut b := "\""
  for c in s.toList do
    match c with
    | '"' => b := b ++ "\\\""
    | '\\' => b := b ++ "\\\\"
    | '\n' => b := b ++ "\\n"
    | '\r' => b := b ++ "\\r"
    | '\t' => b := b ++ "\\t"
    | c =>
      if c.toNat < 32 then b := b ++ "\\u" ++ toHex c.toNat 4
      else b := b.push c
  return b.push '"'

partial def jsonEncode (v : Value) (sort : Bool := false) (indent : Option Nat := none) :
    SIO String := do
  enc v 0
where
  enc (v : Value) (level : Nat) : SIO String := do
    match v with
    | .noval | .null => pure "null"
    | .bool b => pure (if b then "true" else "false")
    | .num n => pure (numToString n)
    | .str s => pure (jsonEscapeStr s)
    | .func _ | .sentinel _ => pure "null"
    | .list id => do
      let xs ← listItems id
      if xs.isEmpty then pure "[]"
      else match indent with
        | some ind => do
          let pad := String.ofList (List.replicate (ind * (level + 1)) ' ')
          let cpad := String.ofList (List.replicate (ind * level) ' ')
          let mut b := "[\n"
          for i in [0:xs.size] do
            if i > 0 then b := b ++ ",\n"
            b := b ++ pad ++ (← enc xs[i]! (level + 1))
          pure (b ++ "\n" ++ cpad ++ "]")
        | none => do
          let mut b := "["
          for i in [0:xs.size] do
            if i > 0 then b := b ++ ","
            b := b ++ (← enc xs[i]! (level + 1))
          pure (b ++ "]")
    | .map id => do
      let es ← mapEntries id
      let ks := es.map (·.1)
      let ks := if sort then ks.qsort strLtB else ks
      if ks.isEmpty then pure "{}"
      else match indent with
        | some ind => do
          let pad := String.ofList (List.replicate (ind * (level + 1)) ' ')
          let cpad := String.ofList (List.replicate (ind * level) ' ')
          let mut b := "{\n"
          for i in [0:ks.size] do
            if i > 0 then b := b ++ ",\n"
            let k := ks[i]!
            b := b ++ pad ++ jsonEscapeStr k ++ ": "
              ++ (← enc ((omapGet es k).getD .noval) (level + 1))
          pure (b ++ "\n" ++ cpad ++ "}")
        | none => do
          let mut b := "{"
          for i in [0:ks.size] do
            if i > 0 then b := b ++ ","
            let k := ks[i]!
            b := b ++ jsonEscapeStr k ++ ":"
              ++ (← enc ((omapGet es k).getD .noval) (level + 1))
          pure (b ++ "}")

/-- Cycle check tracking only the current recursion path (node ids). -/
partial def hasCycle (v : Value) : SIO Bool :=
  go v []
where
  go (v : Value) (seen : List Nat) : SIO Bool := do
    match v with
    | .list id =>
      if seen.contains id then return true
      let xs ← listItems id
      for x in xs do
        if (← go x (id :: seen)) then return true
      return false
    | .map id =>
      if seen.contains id then return true
      let es ← mapEntries id
      for (_, x) in es do
        if (← go x (id :: seen)) then return true
      return false
    | _ => return false

partial def stringify (v : Value) (maxlen : Value := .noval) (pretty : Bool := false) :
    SIO String := do
  match v with
  | .noval => return (if pretty then "<>" else S_MT)
  | _ =>
    let valstr ←
      match v with
      | .str s => pure s
      | _ => do
        if ← hasCycle v then pure "__STRINGIFY_FAILED__"
        else
          try
            pure ((← jsonEncode v (sort := true)).replace "\"" "")
          catch _ => pure "__STRINGIFY_FAILED__"
    let valstr :=
      match maxlen with
      | .num m =>
        if m > -1.0 then
          let mi := fToInt m
          let l : Int := valstr.length
          if mi < l then strTake valstr (max 0 (mi - 3)).toNat ++ "..."
          else valstr
        else valstr
      | _ => valstr
    if pretty then
      let colors : Array Nat := #[81, 118, 213, 39, 208, 201, 45, 190, 129, 51, 160, 121, 226, 33, 207, 69]
      let c := colors.map (fun n => "\x1b[38;5;" ++ toString n ++ "m")
      let r := "\x1b[0m"
      let nc : Int := c.size
      let mut d : Int := 0
      let mut o := c[0]!
      let mut t := c[0]!
      for ch in valstr.toList do
        if ch == '{' || ch == '[' then
          d := d + 1
          o := c[(((d % nc) + nc) % nc).toNat]!
          t := t ++ o ++ String.singleton ch
        else if ch == '}' || ch == ']' then
          t := t ++ o ++ String.singleton ch
          d := d - 1
          o := c[(((d % nc) + nc) % nc).toNat]!
        else
          t := t ++ o ++ String.singleton ch
      return t ++ r
    else return valstr

partial def jsonify (v : Value) (flags : Value := .noval) : SIO String := do
  match v with
  | .noval => return S_NULL
  | _ =>
    let indent ← do
      match (← getprop flags (.str "indent") (.num 2.0)) with
      | .num n => pure (fToInt n)
      | _ => pure (2 : Int)
    try
      let str ← if indent > 0 then jsonEncode v (indent := some indent.toNat)
                else jsonEncode v
      let offset ← do
        match (← getprop flags (.str "offset") (.num 0.0)) with
        | .num n => pure (fToInt n)
        | _ => pure (0 : Int)
      if offset > 0 then
        match str.splitOn "\n" with
        | _ :: rest =>
          let pad := String.ofList (List.replicate offset.toNat ' ')
          return "{\n" ++ String.intercalate "\n" (rest.map (fun l => pad ++ l))
        | [] => return str
      else return str
    catch _ => return S_NULL

partial def pad (s : Value) (padding : Value := .noval) (padchar : Value := .noval) :
    SIO String := do
  let str ← match s with
    | .str x => pure x
    | .null => pure "null"
    | _ => stringify s
  let padn : Int := match padding with
    | .num n => fToInt n
    | _ => 44
  let padc : String := match padchar with
    | .str x => strTake (x ++ " ") 1
    | _ => " "
  if padn > -1 then
    let n : Int := padn - str.length
    if n > 0 then
      return str ++ String.join (List.replicate n.toNat padc)
    else return str
  else
    let n : Int := (-padn) - str.length
    if n > 0 then
      return String.join (List.replicate n.toNat padc) ++ str
    else return str

partial def join (arr : Value) (sep : Value := .noval) (url : Bool := false) :
    SIO String := do
  if !(islist arr) then return S_MT
  let sepdef ← match sep with
    | .noval | .null => pure ","
    | .str s => pure s
    | _ => jsString sep
  let single := sepdef.length == 1
  let sc : Char := if single then sepdef.toList.headD ' ' else ' '
  let itemsArr ← listItemsOf arr
  let sarr := itemsArr.size
  let stripTrailing (s : String) : String := Id.run do
    let a := s.toList.toArray
    let mut i := a.size
    while i > 0 && a[i - 1]! == sc do
      i := i - 1
    return String.ofList (a.extract 0 i).toList
  let stripLeading (s : String) : String := Id.run do
    let a := s.toList.toArray
    let mut i := 0
    while i < a.size && a[i]! == sc do
      i := i + 1
    return String.ofList (a.extract i a.size).toList
  -- Collapse runs of the sep char to one, but only when the run is bounded
  -- by a non-sep char on both sides. Boundary runs are left untouched.
  let collapse (s : String) : String := Id.run do
    let a := s.toList.toArray
    let n := a.size
    let mut b := ""
    let mut i := 0
    while i < n do
      if a[i]! != sc then
        b := b.push a[i]!
        i := i + 1
      else
        let mut j := i
        while j < n && a[j]! == sc do
          j := j + 1
        let beforeNonsep := i > 0 && a[i - 1]! != sc
        let afterNonsep := j < n
        if beforeNonsep && afterNonsep then b := b.push sc
        else b := b ++ String.ofList (a.extract i j).toList
        i := j
    return b
  let mut out : List String := []
  for idx in [0:sarr] do
    match itemsArr[idx]! with
    | .str s =>
      if s != S_MT then
        let s :=
          if single then
            if url && idx == 0 then stripTrailing s
            else
              let s := if idx > 0 then stripLeading s else s
              let s := if idx < sarr - 1 || !url then stripTrailing s else s
              collapse s
          else s
        if s != S_MT then out := s :: out
    | _ => pure ()
  return String.intercalate sepdef out.reverse

partial def joinurl (arr : Value) : SIO String :=
  join arr (sep := .str "/") (url := true)

partial def replace (s from_ to_ : Value) : SIO String := do
  let ts := typify s
  let rs ←
    if (T_STRING &&& ts) == 0 then stringify s
    else if ((T_NOVAL ||| T_NULL) &&& ts) > 0 then pure S_MT
    else stringify s
  let toS ← match to_ with
    | .str x => pure x
    | _ => jsString to_
  match from_ with
  | .str f =>
    if f == "" then return rs
    else return rs.replace f toS
  | _ => return rs

partial def pathify (v : Value) (startin : Value := .noval) (endin : Value := .noval)
    (absent : Bool := false) : SIO String := do
  let path ←
    if islist v then pure (some (← listItemsOf v))
    else if iskey v then pure (some #[v])
    else pure none
  let start : Nat := match startin with
    | .num n => if n > -1.0 then (fToInt n).toNat else 0
    | _ => 0
  let endn : Nat := match endin with
    | .num n => if n > -1.0 then (fToInt n).toNat else 0
    | _ => 0
  let pathstr ←
    match path with
    | some p => do
      let len := p.size
      let e := len - endn         -- Nat subtraction: floors at 0 (max 0 in OCaml)
      let s := min start len
      let sub := if s <= e then p.extract s e else #[]
      if sub.isEmpty then pure (some "<root>")
      else do
        let fp := sub.filter iskey
        let mut mapped : List String := []
        for pp in fp do
          match pp with
          | .num n => mapped := numToString n.floor :: mapped
          | _ => mapped := ((← jsString pp).replace "." "") :: mapped
        pure (some (String.intercalate "." mapped.reverse))
    | none => pure none
  match pathstr with
  | some s => return s
  | none => do
    let suffix ← if absent then pure S_MT
      else do pure (S_CN ++ (← stringify v (maxlen := .num 47.0)))
    return "<unknown-path" ++ suffix ++ ">"

-- ---------------------------------------------------------------------------
-- walk
-- ---------------------------------------------------------------------------

/-- Walk callbacks receive `key value parent path`. -/
abbrev WalkFn := Value → Value → Value → Value → SIO Value

partial def walk (v : Value) (before : Option WalkFn := none)
    (after : Option WalkFn := none) (maxdepth : Value := .noval)
    (key : Value := .noval) (parent : Value := .noval)
    (path : Option Value := none) : SIO Value := do
  let path ← match path with
    | some p => pure p
    | none => emptyList
  let depth ← size path
  let out0 ← match before with
    | none => pure v
    | some f => f key v parent path
  let mdv : Int := match maxdepth with
    | .num n => if n >= 0.0 then fToInt n else MAXDEPTH
    | .noval | .null => MAXDEPTH
    | _ => MAXDEPTH
  if mdv == 0 || (mdv > 0 && mdv <= depth) then return out0
  if isnode out0 then
    let pfx ← listItemsOf path
    let pairs ← itemsPairs out0
    for (ckey, child) in pairs do
      let childpath ← newList (pfx.push (.str ckey))
      let result ← walk child before after (.num (intToFloat mdv)) (.str ckey)
        out0 (some childpath)
      match out0 with
      | .map id => mapSetKV id ckey result
      | .list id => do
        match strToInt? ckey with
        | some i =>
          if i >= 0 then do
            let xs ← listItems id
            if i < (xs.size : Int) then setListItems id (xs.set! i.toNat result)
        | none => pure ()
      | _ => pure ()
  match after with
  | none => return out0
  | some f => f key out0 parent path

-- ---------------------------------------------------------------------------
-- merge
-- ---------------------------------------------------------------------------

partial def merge (objs : Value) (maxdepth : Value := .noval) : SIO Value := do
  let md : Int := match maxdepth with
    | .num n => if n < 0.0 then 0 else fToInt n
    | .noval | .null => 32
    | _ => 32
  if !(islist objs) then return objs
  let l ← listItemsOf objs
  let lenlist := l.size
  if lenlist == 0 then return .noval
  if lenlist == 1 then return l[0]!
  let outRef ← IO.mkRef (← getprop objs (.num 0.0) (← emptyMap))
  for oi in [1:lenlist] do
    let obj := l[oi]!
    if !(isnode obj) then
      outRef.set obj
    else
      let cur ← IO.mkRef #[← outRef.get]
      let dst ← IO.mkRef #[← outRef.get]
      let grow (r : IO.Ref (Array Value)) (n : Nat) : SIO Unit := do
        let a ← r.get
        if a.size <= n then
          r.set (a ++ Array.replicate (n + 1 - a.size) Value.noval)
      let before : WalkFn := fun key v _parent path => do
        let pi ← size path
        let piN := pi.toNat
        if md <= pi then do
          grow cur piN
          cur.modify (·.set! piN v)
          if pi > 0 then do
            let target := (← cur.get)[piN - 1]!
            let _ ← setprop target key v
          pure .noval
        else if !(isnode v) then do
          grow cur piN
          cur.modify (·.set! piN v)
          pure v
        else do
          grow dst piN
          grow cur piN
          let dprev ← if piN > 0 then do
              pure ((← dst.get)[piN - 1]!)
            else do
              pure ((← dst.get)[piN]!)
          let tval ← if piN > 0 then getprop dprev key else pure dprev
          dst.modify (·.set! piN tval)
          if isNullish tval then do
            let fresh ← if islist v then emptyList else emptyMap
            cur.modify (·.set! piN fresh)
            pure v
          else if (islist v && islist tval) || (ismap v && ismap tval) then do
            cur.modify (·.set! piN tval)
            pure v
          else do
            cur.modify (·.set! piN v)
            pure .noval
      let after : WalkFn := fun key v _parent path => do
        let ci ← size path
        let ciN := ci.toNat
        if ci < 1 then do
          let a ← cur.get
          if a.size > 0 then pure a[0]! else pure v
        else do
          let a ← cur.get
          let target := if ciN - 1 < a.size then a[ciN - 1]! else .noval
          let value := if ciN < a.size then a[ciN]! else .noval
          let _ ← setprop target key value
          pure value
      outRef.set (← walk obj (before := some before) (after := some after))
  if md == 0 then do
    let o ← getprop objs (vInt ((lenlist : Int) - 1))
    let res ← if islist o then emptyList else if ismap o then emptyMap else pure o
    outRef.set res
  outRef.get

-- ---------------------------------------------------------------------------
-- string-pattern helpers (hand-rolled, RE2-subset-free)
-- ---------------------------------------------------------------------------

/-- R_META_PATH = `^([^$]+)\$([=~])(.+)$` -/
def metaPathMatch (s : String) : Option (String × String × String) := Id.run do
  let cs := s.toList.toArray
  let n := cs.size
  let mut di : Option Nat := none
  for i in [0:n] do
    if di.isNone && cs[i]! == '$' then di := some i
  match di with
  | some i =>
    if i > 0 && i + 1 < n && (cs[i + 1]! == '=' || cs[i + 1]! == '~') && i + 2 <= n - 1 then
      return some (String.ofList (cs.extract 0 i).toList,
                   String.singleton cs[i + 1]!,
                   String.ofList (cs.extract (i + 2) n).toList)
    else return none
  | none => return none

/-- R_INJECTION_FULL: whole string is a single backtick injection; returns the
    captured reference ($NAME with trailing digits stripped, or the literal). -/
def injectionFull (s : String) : Option String := Id.run do
  let cs := s.toList.toArray
  let n := cs.size
  if n >= 2 && cs[0]! == '`' && cs[n - 1]! == '`' then
    let inner := cs.extract 1 (n - 1)
    if inner.contains '`' then return none
    -- $[A-Z]+[0-9]*$ -> group is $ + uppercase run
    let ilen := inner.size
    if ilen > 1 && inner[0]! == '$' then
      let mut j := 1
      while j < ilen && inner[j]! >= 'A' && inner[j]! <= 'Z' do
        j := j + 1
      let lettersEnd := j
      let mut k := lettersEnd
      while k < ilen && inner[k]! >= '0' && inner[k]! <= '9' do
        k := k + 1
      if lettersEnd > 1 && k == ilen then
        return some (String.ofList (inner.extract 0 lettersEnd).toList)
    return some (String.ofList inner.toList)
  else return none

/-- Replace each backtick pair (R_INJECTION_PARTIAL) using f on the inner text. -/
partial def injectionPartialReplace (s : String) (f : String → SIO String) : SIO String := do
  let cs := s.toList.toArray
  let n := cs.size
  let mut b := ""
  let mut i := 0
  while i < n do
    if cs[i]! == '`' then
      let mut j := i + 1
      while j < n && cs[j]! != '`' do
        j := j + 1
      if j < n then
        let inner := String.ofList (cs.extract (i + 1) j).toList
        b := b ++ (← f inner)
        i := j + 1
      else
        b := b.push cs[i]!
        i := i + 1
    else
      b := b.push cs[i]!
      i := i + 1
  return b

/-- Replace `` `$NAME` `` with `name` (lowercase); used in validate errors. -/
def replaceTransformNames (s : String) : String := Id.run do
  let cs := s.toList.toArray
  let n := cs.size
  let mut b := ""
  let mut i := 0
  while i < n do
    if cs[i]! == '`' && i + 1 < n && cs[i + 1]! == '$' then
      let mut j := i + 2
      while j < n && cs[j]! >= 'A' && cs[j]! <= 'Z' do
        j := j + 1
      if j < n && cs[j]! == '`' && j > i + 2 then
        b := b ++ (String.ofList (cs.extract (i + 2) j).toList).toLower
        i := j + 1
      else
        b := b.push cs[i]!
        i := i + 1
    else
      b := b.push cs[i]!
      i := i + 1
  return b

-- ---------------------------------------------------------------------------
-- getpath / setpath
-- ---------------------------------------------------------------------------

def iaIsSome : InjArg → Bool
  | .inone => false
  | _ => true

def iaBase (a : InjArg) : SIO Value := do
  match a with
  | .iinj i => pure (← getInj i).base
  | .idef d => pure d.dBase
  | .inone => pure .noval

def iaDparent (a : InjArg) : SIO Value := do
  match a with
  | .iinj i => pure (← getInj i).dparent
  | .idef d => pure d.dDparent
  | .inone => pure .noval

def iaMeta (a : InjArg) : SIO Value := do
  match a with
  | .iinj i => pure (← getInj i).imeta
  | .idef d => pure d.dMeta
  | .inone => pure .noval

def iaKey (a : InjArg) : SIO Value := do
  match a with
  | .iinj i => pure (← getInj i).key
  | .idef d => pure d.dKey
  | .inone => pure .noval

def iaDpath (a : InjArg) : SIO Value := do
  match a with
  | .iinj i => pure (← getInj i).dpath
  | .idef d => pure d.dDpath
  | .inone => pure .noval

def iaHandler (a : InjArg) : SIO (Option Nat) := do
  match a with
  | .iinj i => pure (some (← getInj i).handler)
  | .idef d => pure d.dHandler
  | .inone => pure none

partial def getpath (store path : Value) (inj : InjArg := .inone) : SIO Value := do
  let pa0 : Option (Array Value) ←
    match path with
    | .list _ => pure (some (← listItemsOf path))
    | .str s => pure (some ((s.splitOn ".").map (fun x => Value.str x)).toArray)
    | .num n => pure (some #[.str (strkey (.num n))])
    | _ => pure none
  match pa0 with
  | none => return .noval
  | some pa0 => do
    let paRef ← IO.mkRef pa0
    let base ← iaBase inj
    let dparent ← iaDparent inj
    let injMeta ← iaMeta inj
    let injKey ← iaKey inj
    let dpath ← iaDpath inj
    let src ← if iskey base then getprop store base store else pure store
    let numparts := pa0.size
    let vRef ← IO.mkRef store
    let arrGet (i : Int) : SIO Value := do
      let pa ← paRef.get
      if i >= 0 && i < (pa.size : Int) then pure pa[i.toNat]! else pure .noval
    if isNoval path || isNoval store
        || (numparts == 1 && pa0[0]! == .str S_MT) || numparts == 0 then
      vRef.set src
    else do
      if numparts == 1 then
        vRef.set (← getprop store pa0[0]!)
      if !(isfunc (← vRef.get)) then do
        vRef.set src
        (match pa0[0]! with
         | .str s0 =>
           match metaPathMatch s0 with
           | some (g1, _, g3) => do
             if !(isNoval injMeta) && iaIsSome inj then do
               vRef.set (← getprop injMeta (.str g1))
               paRef.modify (·.set! 0 (.str g3))
           | none => pure ()
         | _ => pure ())
        let piRef ← IO.mkRef (0 : Nat)
        let contRef ← IO.mkRef true
        repeat do
          let cont ← contRef.get
          let pi ← piRef.get
          if !cont || isNoval (← vRef.get) || pi >= numparts then break
          let raw := (← paRef.get)[pi]!
          let part ←
            match raw with
            | .str s =>
              if iaIsSome inj && s == S_DKEY then
                pure (if !(isNoval injKey) then injKey else raw)
              else if s.startsWith "$GET:" then do
                let sub ← slice (.str s) (start := .num 5.0) (stop := .num (-1.0))
                pure (Value.str (← stringify (← getpath src sub)))
              else if s.startsWith "$REF:" then do
                let sub ← slice (.str s) (start := .num 5.0) (stop := .num (-1.0))
                pure (Value.str (← stringify (← getpath (← getprop store (.str S_DSPEC)) sub)))
              else if iaIsSome inj && s.startsWith "$META:" then do
                let sub ← slice (.str s) (start := .num 6.0) (stop := .num (-1.0))
                pure (Value.str (← stringify (← getpath injMeta sub)))
              else pure raw
            | _ => pure raw
          -- $$ escapes $
          let part : Value :=
            match part with
            | .str s => .str (if strContains s '$' then s.replace "$$" "$" else s)
            | _ => .str (strkey part)
          if part == .str S_MT then do
            let ascendsRef ← IO.mkRef (0 : Nat)
            repeat do
              let pi' ← piRef.get
              if (← arrGet ((pi' : Int) + 1)) == .str S_MT then
                ascendsRef.modify (· + 1)
                piRef.modify (· + 1)
              else break
            let ascends0 ← ascendsRef.get
            if iaIsSome inj && ascends0 > 0 then do
              let pi' ← piRef.get
              if pi' == numparts - 1 then ascendsRef.modify (· - 1)
              let ascends ← ascendsRef.get
              if ascends == 0 then vRef.set dparent
              else do
                let pa ← paRef.get
                let pi'' ← piRef.get
                let tailparts := pa.extract (pi'' + 1) numparts
                let dsliced ← slice dpath (start := .num (intToFloat (-(ascends : Int))))
                let tailV ← newList tailparts
                let fullpath ← flatten (← newList #[dsliced, tailV])
                if (ascends : Int) <= (← size dpath) then
                  vRef.set (← getpath store fullpath)
                else
                  vRef.set .noval
                contRef.set false
            else vRef.set dparent
          else
            vRef.set (← getprop (← vRef.get) part)
          if ← contRef.get then piRef.modify (· + 1)
    let handlerOpt ← iaHandler inj
    match handlerOpt with
    | some h =>
      if iaIsSome inj then do
        let refp ← pathify path
        let i ← match inj with
          | .iinj i => pure i
          | _ => getDummyInj
        vRef.set (← callFunc h i (← vRef.get) refp store)
    | none => pure ()
    vRef.get

partial def setpath (store path v : Value) (inj : InjArg := .inone) : SIO Value := do
  let ptype := typify path
  let parts ←
    if (T_LIST &&& ptype) > 0 then do
      pure (some (← newList (← listItemsOf path)))
    else if (T_STRING &&& ptype) > 0 then do
      match path with
      | .str s => pure (some (← newList ((s.splitOn ".").map (fun x => Value.str x)).toArray))
      | _ => pure (some (← emptyList))
    else if (T_NUMBER &&& ptype) > 0 then do
      pure (some (← newList #[path]))
    else pure none
  match parts with
  | none => return .noval
  | some parts => do
    let base ← match inj with
      | .inone => pure Value.noval
      | _ => iaBase inj
    let numparts ← size parts
    let n := numparts.toNat
    let parentRef ← IO.mkRef (← if iskey base then getprop store base store else pure store)
    for pi in [0:n-1] do
      let pkey ← getelem parts (vInt pi)
      let np ← getprop (← parentRef.get) pkey
      let np ← if !(isnode np) then do
          let nextpart ← getelem parts (vInt ((pi : Int) + 1))
          let nn ← if (T_NUMBER &&& typify nextpart) > 0 then emptyList else emptyMap
          let _ ← setprop (← parentRef.get) pkey nn
          pure nn
        else pure np
      parentRef.set np
    let lastkey ← getelem parts (.num (-1.0))
    if isDelete v then
      let _ ← delprop (← parentRef.get) lastkey
    else
      let _ ← setprop (← parentRef.get) lastkey v
    parentRef.get

-- ---------------------------------------------------------------------------
-- Injection state
-- ---------------------------------------------------------------------------

def newInj (v parent : Value) : SIO InjId := do
  let keys ← newList #[.str S_DTOP]
  let path ← newList #[.str S_DTOP]
  let nodes ← newList #[parent]
  let errs ← emptyList
  let meta0 ← emptyMap
  let dpath ← newList #[.str S_DTOP]
  let h ← (← read).injectHandlerFid.get
  newInjData {
    mode := M_VAL, full := false, keyi := 0, keys, key := .str S_DTOP, ival := v,
    parent, path, nodes, handler := h, errs, imeta := meta0, dparent := .noval,
    dpath, base := .str S_DTOP, modify := none, prior := none, extra := .noval }

partial def injDescend (i : InjId) : SIO Value := do
  let d ← getInj i
  (match d.imeta with
   | .map mid => do
     let es ← mapEntries mid
     let dv := match omapGet es "__d" with
       | some (.num n) => n
       | _ => 0.0
     mapSetKV mid "__d" (.num (dv + 1.0))
   | _ => pure ())
  let parentkey ← getelem d.path (.num (-2.0))
  if isNoval d.dparent then do
    if (← size d.dpath) > 1 then
      match d.dpath with
      | .list r => do
        let xs ← listItems r
        let nl ← newList (xs.push parentkey)
        modInj i (fun dd => { dd with dpath := nl })
      | _ => pure ()
  else if !(isNoval parentkey) then do
    let ndp ← getprop d.dparent parentkey
    modInj i (fun dd => { dd with dparent := ndp })
    let d2 ← getInj i
    let lastpart ← getelem d2.dpath (.num (-1.0))
    let pkstr ← jsString parentkey
    if lastpart == .str ("$:" ++ pkstr) then do
      let ndpath ← slice d2.dpath (start := .num (-1.0))
      modInj i (fun dd => { dd with dpath := ndpath })
    else
      match d2.dpath with
      | .list r => do
        let xs ← listItems r
        let nl ← newList (xs.push parentkey)
        modInj i (fun dd => { dd with dpath := nl })
      | _ => pure ()
  pure (← getInj i).dparent

/-- Create a child Injection (internal; the canonical public `injectChild`
    helper is defined further below). -/
partial def makeChildInj (i : InjId) (keyi : Int) (keys : Value) : SIO InjId := do
  let d ← getInj i
  let kElem ← getelem keys (vInt keyi)
  let key := strkey kElem
  let v := d.ival
  let ival ← getprop v (.str key)
  let path ← match d.path with
    | .list r => do newList ((← listItems r).push (.str key))
    | _ => newList #[.str key]
  let nodes ← match d.nodes with
    | .list r => do newList ((← listItems r).push v)
    | _ => newList #[v]
  let dpath ← match d.dpath with
    | .list r => do newList (← listItems r)
    | _ => pure d.dpath
  newInjData { d with
    keyi, keys, key := .str key, ival, parent := v, path, nodes,
    prior := some i, dpath }

partial def injSetval (i : InjId) (v : Value) (ancestor : Int := 1) : SIO Unit := do
  let d ← getInj i
  let (target, key) ←
    if ancestor < 2 then pure (d.parent, d.key)
    else do
      let t ← getelem d.nodes (vInt (-ancestor))
      let k ← getelem d.path (vInt (-ancestor))
      pure (t, k)
  if isNoval v then
    let _ ← delprop target key
  else
    let _ ← setprop target key v

-- ---------------------------------------------------------------------------
-- inject
-- ---------------------------------------------------------------------------

def pushErr (i : InjId) (msg : String) : SIO Unit := do
  let d ← getInj i
  let n ← size d.errs
  let _ ← setprop d.errs (vInt n) (.str msg)

mutual

partial def inject (v : Value) (store : Value) (inj : InjArg := .inone) : SIO Value := do
  let state ←
    match inj with
    | .iinj i => pure i
    | _ => do
      let parent ← newMap #[(S_DTOP, v)]
      let i ← newInj v parent
      let errsV ← getprop store (.str S_DERRS) (← emptyList)
      modInj i (fun d => { d with dparent := store, errs := errsV })
      (match (← getInj i).imeta with
       | .map mid => mapSetKV mid "__d" (.num 0.0)
       | _ => pure ())
      (match inj with
       | .idef dd => do
         if dd.dModify.isSome then modInj i (fun d => { d with modify := dd.dModify })
         if !(isNoval dd.dExtra) then modInj i (fun d => { d with extra := dd.dExtra })
         if !(isNoval dd.dMeta) then modInj i (fun d => { d with imeta := dd.dMeta })
         (match dd.dHandler with
          | some h => modInj i (fun d => { d with handler := h })
          | none => pure ())
       | _ => pure ())
      pure i
  let _ ← injDescend state
  let v ←
    if isnode v then do
      let nodekeys0 : Array String ←
        match v with
        | .map mid => do
          let es ← mapEntries mid
          let ks := es.map (·.1)
          let normal := (ks.filter (fun k => !(strContains k '$'))).qsort strLtB
          let trans := (ks.filter (fun k => strContains k '$')).qsort strLtB
          pure (normal ++ trans)
        | .list lid => do
          let xs ← listItems lid
          pure ((Array.range xs.size).map (fun i => toString i))
        | _ => pure #[]
      let nodekeysRef ← IO.mkRef nodekeys0
      let rereadKeys (ci : InjId) : SIO Unit := do
        match (← getInj ci).keys with
        | .list r => do
          let xs ← listItems r
          let mut out : Array String := #[]
          for x in xs do
            out := out.push (← jsString x)
          nodekeysRef.set out
        | _ => nodekeysRef.set #[]
      let mut nki : Int := 0
      repeat do
        let nodekeys ← nodekeysRef.get
        if nki >= (nodekeys.size : Int) then break
        let keysV ← newList (nodekeys.map (fun s => Value.str s))
        let ci ← makeChildInj state nki keysV
        let nodekey := (← getInj ci).key
        modInj ci (fun d => { d with mode := M_KEYPRE })
        let prekey ← injectstr (← jsString nodekey) store (some ci)
        rereadKeys ci
        if !(isNoval prekey) then do
          let iv ← getprop v prekey
          modInj ci (fun d => { d with ival := iv, mode := M_VAL })
          let _ ← inject iv store (.iinj ci)
          rereadKeys ci
          modInj ci (fun d => { d with mode := M_KEYPOST })
          let _ ← injectstr (← jsString nodekey) store (some ci)
          rereadKeys ci
        nki := (← getInj ci).keyi + 1
      pure v
    else if (match v with | .str _ => true | _ => false) then do
      modInj state (fun d => { d with mode := M_VAL })
      let nv ← injectstr (← jsString v) store (some state)
      if !(isSkip nv) then injSetval state nv
      pure nv
    else pure v
  let d ← getInj state
  (match d.modify with
   | some mid =>
     if !(isSkip v) then do
       let mkey := d.key
       let mparent := d.parent
       let mval ← getprop mparent mkey
       callModify mid mval mkey mparent state
     else pure ()
   | none => pure ())
  modInj state (fun dd => { dd with ival := v })
  lookupRaw d.parent (.str S_DTOP)

partial def injectHandler : InjectorFn := fun inj v refstr store => do
  let iscmd := isfunc v && (refstr == "" || refstr.startsWith S_DS)
  if iscmd then
    match v with
    | .func fid => callFunc fid inj v refstr store
    | _ => pure v
  else do
    let d ← getInj inj
    if d.mode == M_VAL && d.full then do
      injSetval inj v
      pure v
    else pure v

partial def injectstr (v : String) (store : Value) (injOpt : Option InjId) : SIO Value := do
  if v == S_MT then return .str S_MT
  match injectionFull v with
  | some pathref0 => do
    (match injOpt with
     | some i => modInj i (fun d => { d with full := true })
     | none => pure ())
    let pathref :=
      if pathref0.length > 3 then (pathref0.replace "$BT" S_BT).replace "$DS" S_DS
      else pathref0
    let ia := match injOpt with
      | some i => InjArg.iinj i
      | none => .inone
    getpath store (.str pathref) ia
  | none => do
    let out ← injectionPartialReplace v (fun ref0 => do
      let refp :=
        if ref0.length > 3 then (ref0.replace "$BT" S_BT).replace "$DS" S_DS
        else ref0
      (match injOpt with
       | some i => modInj i (fun d => { d with full := false })
       | none => pure ())
      let ia := match injOpt with
        | some i => InjArg.iinj i
        | none => .inone
      let found ← getpath store (.str refp) ia
      match found with
      | .noval => pure S_MT
      | .str s => pure (if s == "__NULL__" then "null" else s)
      | .func _ => pure S_MT
      | _ => try jsonEncode found catch _ => stringify found)
    match injOpt with
    | some i => do
      modInj i (fun d => { d with full := true })
      callFunc (← getInj i).handler i (.str out) v store
    | none => pure (.str out)

end

-- ---------------------------------------------------------------------------
-- transform commands
-- ---------------------------------------------------------------------------

partial def transformDelete : InjectorFn := fun inj _v _ref _store => do
  let d ← getInj inj
  let _ ← delprop d.parent d.key
  pure .noval

partial def transformCopy : InjectorFn := fun inj _v _ref _store => do
  let d ← getInj inj
  if d.mode == M_KEYPRE || d.mode == M_KEYPOST then pure d.key
  else do
    let out ← lookupRaw d.dparent d.key
    injSetval inj out
    pure out

partial def transformKey : InjectorFn := fun inj _v _ref _store => do
  let d ← getInj inj
  if d.mode != M_VAL then pure .noval
  else do
    let keyspec ← lookupRaw d.parent (.str S_BKEY)
    if !(isNoval keyspec) then do
      let _ ← delprop d.parent (.str S_BKEY)
      getprop d.dparent keyspec
    else do
      let anno ← lookupRaw d.parent (.str S_BANNO)
      let fromanno ← lookupRaw anno (.str S_KEY)
      if !(isNoval fromanno) then pure fromanno
      else getelem d.path (.num (-2.0))

partial def transformAnno : InjectorFn := fun inj _v _ref _store => do
  let d ← getInj inj
  let _ ← delprop d.parent (.str S_BANNO)
  pure .noval

partial def transformMerge : InjectorFn := fun inj _v _ref _store => do
  let d ← getInj inj
  if d.mode == M_KEYPRE then pure d.key
  else if d.mode == M_KEYPOST then do
    let args0 ← getprop d.parent d.key
    let args ← if islist args0 then pure args0 else newList #[args0]
    injSetval inj .noval
    let pl ← newList #[d.parent]
    let cl ← newList #[← clone d.parent]
    let mergelist ← flatten (← newList #[pl, args, cl])
    let _ ← merge mergelist
    pure d.key
  else pure .noval

partial def transformEach : InjectorFn := fun inj _v _ref store => do
  let d0 ← getInj inj
  if islist d0.keys then
    let _ ← slice d0.keys (start := .num 0.0) (stop := .num 1.0) (mutate := true)
  if d0.mode != M_VAL then pure .noval
  else do
    let d ← getInj inj
    let parent := d.parent
    let psize ← size parent
    let srcpath ← if psize > 1 then getelem parent (.num 1.0) else pure .noval
    let childTm ← if psize > 2 then clone (← getelem parent (.num 2.0)) else pure .noval
    let srcstore ← getprop store d.base store
    let src ← getpath srcstore srcpath (.iinj inj)
    let tkey ← getelem d.path (.num (-2.0))
    let nodes := d.nodes
    let target ← do
      let t ← getelem nodes (.num (-2.0))
      if isNullish t then getelem nodes (.num (-1.0)) else pure t
    let rvalRef ← IO.mkRef (← emptyList)
    if isnode src then do
      let mut tval : Array Value := #[]
      match src with
      | .list r =>
        for _ in (← listItems r) do
          tval := tval.push (← clone childTm)
      | .map m =>
        for (k, _) in (← mapEntries m) do
          let cc ← clone childTm
          if ismap cc then
            let _ ← setprop cc (.str S_BANNO) (← newMap #[(S_KEY, .str k)])
          tval := tval.push cc
      | _ => pure ()
      let tvalv ← newList tval
      let tcurrent ← match src with
        | .map m => do newList ((← mapEntries m).map (·.2))
        | .list r => do newList (← listItems r)
        | _ => pure src
      if tval.size > 0 then do
        let path := d.path
        let ckey ← getelem path (.num (-2.0))
        let plist ← listItemsOf path
        let tpath ← newList (if plist.isEmpty then #[] else plist.extract 0 (plist.size - 1))
        let mut dpathArr : Array Value := #[.str S_DTOP]
        match srcpath with
        | .str sp =>
          if sp != S_MT then
            for p in sp.splitOn "." do
              if p != S_MT then dpathArr := dpathArr.push (.str p)
        | _ => pure ()
        let ckstr ← jsString ckey
        if !(isNoval ckey) then dpathArr := dpathArr.push (.str ("$:" ++ ckstr))
        let tcurRef ← IO.mkRef (← newMap #[(ckstr, tcurrent)])
        if (← size tpath) > 1 then do
          let pkey ← getelem path (.num (-3.0)) (.str S_DTOP)
          let pkstr ← jsString pkey
          dpathArr := dpathArr.push (.str ("$:" ++ pkstr))
          tcurRef.set (← newMap #[(pkstr, ← tcurRef.get)])
        let keys0 ← if !(isNoval ckey) then newList #[ckey] else emptyList
        let tinj ← makeChildInj inj 0 keys0
        let nlist ← listItemsOf nodes
        let tnodes ← newList (if nlist.isEmpty then #[] else nlist.extract 0 (nlist.size - 1))
        modInj tinj (fun dd => { dd with path := tpath, nodes := tnodes })
        let tparent ← do
          if (← size tnodes) > 0 then getelem tnodes (.num (-1.0)) else pure .noval
        modInj tinj (fun dd => { dd with parent := tparent })
        if !(isNoval ckey) && !(isNoval tparent) then
          let _ ← setprop tparent ckey tvalv
        let dpathV ← newList dpathArr
        let tcur ← tcurRef.get
        modInj tinj (fun dd => { dd with
          ival := tvalv, dpath := dpathV, dparent := tcur })
        let _ ← inject tvalv store (.iinj tinj)
        rvalRef.set (← getInj tinj).ival
      else pure ()
    let rval ← rvalRef.get
    let _ ← setprop target tkey rval
    if islist rval && (← size rval) > 0 then getelem rval (.num 0.0) else pure .noval

partial def transformPack : InjectorFn := fun inj _v _ref store => do
  let d ← getInj inj
  if d.mode != M_KEYPRE || !(match d.key with | .str _ => true | _ => false) then
    pure .noval
  else do
    let parent := d.parent
    let path := d.path
    let nodes := d.nodes
    let argsVal ← getprop parent d.key
    if !(islist argsVal) || (← size argsVal) < 2 then pure .noval
    else do
      let srcpath ← getelem argsVal (.num 0.0)
      let origchildspec ← getelem argsVal (.num 1.0)
      let tkey ← getelem path (.num (-2.0))
      let pathsize ← size path
      let target ← do
        let t ← getelem nodes (vInt (pathsize - 2))
        if isNullish t then getelem nodes (vInt (pathsize - 1)) else pure t
      let srcstore ← getprop store d.base store
      let src0 ← getpath srcstore srcpath (.iinj inj)
      let src ←
        if !(islist src0) then
          if ismap src0 then do
            let ps ← itemsPairs src0
            let mut arr : Array Value := #[]
            for (k, node) in ps do
              let _ ← setprop node (.str S_BANNO) (← newMap #[(S_KEY, .str k)])
              arr := arr.push node
            newList arr
          else pure Value.noval
        else pure src0
      if isNoval src then pure .noval
      else do
        let keypath ← getprop origchildspec (.str S_BKEY)
        let childspec ← delprop origchildspec (.str S_BKEY)
        let child ← getprop childspec (.str S_BVAL) childspec
        let tval ← emptyMap
        let packKey (node : Value) (fallback : Value) : SIO Value := do
          if isNoval keypath then pure fallback
          else match keypath with
            | .str kp =>
              if kp.startsWith S_BT then do
                let em ← emptyMap
                let wrap ← newMap #[(S_DTOP, node)]
                let m ← merge (← newList #[em, store, wrap]) (maxdepth := .num 1.0)
                inject (.str kp) m
              else getpath node keypath (.iinj inj)
            | _ => getpath node keypath (.iinj inj)
        for (srckey, srcnode) in (← itemsPairs src) do
          let k ← packKey srcnode (.str srckey)
          let tchild ← clone child
          let _ ← setprop tval k tchild
          let anno ← getprop srcnode (.str S_BANNO)
          if isNoval anno then
            let _ ← delprop tchild (.str S_BANNO)
          else
            let _ ← setprop tchild (.str S_BANNO) anno
        let rvalRef ← IO.mkRef (← emptyMap)
        if !(← isempty tval) then do
          let tsrc ← emptyMap
          let srcItems ← listItemsOf src
          for i in [0:srcItems.size] do
            let node := srcItems[i]!
            let kn ← packKey node (vInt i)
            let _ ← setprop tsrc kn node
          let tpath ← slice d.path (start := .num (-1.0))
          let ckey ← getelem d.path (.num (-2.0))
          let mut dpathArr : Array Value := #[.str S_DTOP]
          match srcpath with
          | .str sp =>
            for p in sp.splitOn "." do
              if p != S_MT then dpathArr := dpathArr.push (.str p)
          | _ => pure ()
          let ckstr ← jsString ckey
          dpathArr := dpathArr.push (.str ("$:" ++ ckstr))
          let tcurRef ← IO.mkRef (← newMap #[(ckstr, tsrc)])
          if (← size tpath) > 1 then do
            let pkey ← getelem d.path (.num (-3.0)) (.str S_DTOP)
            let pkstr ← jsString pkey
            dpathArr := dpathArr.push (.str ("$:" ++ pkstr))
            tcurRef.set (← newMap #[(pkstr, ← tcurRef.get)])
          let tinj ← makeChildInj inj 0 (← newList #[ckey])
          let tnodes ← slice d.nodes (start := .num (-1.0))
          modInj tinj (fun dd => { dd with path := tpath, nodes := tnodes })
          let tparent ← getelem tnodes (.num (-1.0))
          let dpathV ← newList dpathArr
          let tcur ← tcurRef.get
          modInj tinj (fun dd => { dd with
            parent := tparent, ival := tval, dpath := dpathV, dparent := tcur })
          let _ ← inject tval store (.iinj tinj)
          rvalRef.set (← getInj tinj).ival
        let _ ← setprop target tkey (← rvalRef.get)
        pure .noval

partial def transformRef : InjectorFn := fun inj v _ref store => do
  let d ← getInj inj
  if d.mode != M_VAL then pure .noval
  else do
    let nodes := d.nodes
    let refpath ← lookupRaw d.parent (.num 1.0)
    let nkeys ← size d.keys
    modInj inj (fun dd => { dd with keyi := nkeys })
    let specFunc ← getprop store (.str S_DSPEC)
    match specFunc with
    | .func fid => do
      let spec ← callFunc fid inj .noval "" .noval
      let refv ← getpath spec refpath
      let hasSub ← IO.mkRef false
      if isnode refv then
        let _ ← walk refv (before := some (fun _k v2 _p _path => do
          if v2 == .str "`$REF`" then hasSub.set true
          pure v2))
      let tref ← clone refv
      let d2 ← getInj inj
      let psize ← size d2.path
      let cpath ← slice d2.path (start := .num 0.0) (stop := vInt (psize - 3))
      let tpath ← slice d2.path (start := .num 0.0) (stop := vInt (psize - 1))
      let tcur ← getpath store cpath
      let tval ← getpath store tpath
      let rvalRef ← IO.mkRef Value.noval
      let hs ← hasSub.get
      if !(isNoval refv) && (!hs || !(isNoval tval)) then do
        let lastp ← getelem tpath (.num (-1.0))
        let cs ← makeChildInj inj 0 (← newList #[lastp])
        let nsize ← size d2.nodes
        let cnodes ← slice d2.nodes (start := .num 0.0) (stop := vInt (nsize - 1))
        let cparent ← getelem nodes (.num (-2.0))
        modInj cs (fun dd => { dd with
          path := tpath, nodes := cnodes, parent := cparent,
          ival := tref, dparent := tcur })
        let _ ← inject tref store (.iinj cs)
        rvalRef.set (← getInj cs).ival
      injSetval inj (← rvalRef.get) (ancestor := 2)
      let d3 ← getInj inj
      (match d3.prior with
       | some p =>
         if islist d3.parent then
           modInj p (fun dd => { dd with keyi := dd.keyi - 1 })
         else pure ()
       | none => pure ())
      pure v
    | _ => pure .noval

-- ---------------------------------------------------------------------------
-- $FORMAT formatters / placement checks / argument checks
-- ---------------------------------------------------------------------------

partial def formatterTbl : List (String × (Value → Value → SIO Value)) := [
  ("identity", fun _k v => pure v),
  ("upper", fun _k v => do
    if isnode v then pure v else pure (.str (← jsString v).toUpper)),
  ("lower", fun _k v => do
    if isnode v then pure v else pure (.str (← jsString v).toLower)),
  ("string", fun _k v => do
    if isnode v then pure v else pure (.str (← jsString v))),
  ("number", fun _k v => do
    if isnode v then pure v
    else do
      let n := (parseFloatJS (← jsString v)).getD 0.0
      let n := if n.isNaN then 0.0 else n
      pure (.num n)),
  ("integer", fun _k v => do
    if isnode v then pure v
    else do
      let n := (parseFloatJS (← jsString v)).getD 0.0
      let n := if n.isNaN then 0.0 else n
      pure (.num (intToFloat (fToInt n)))),
  ("concat", fun k v => do
    if isNoval k && islist v then do
      let parts ← itemsV v (fun (_, x) => do
        if isnode x then pure (Value.str S_MT) else pure (Value.str (← jsString x)))
      pure (.str (← join parts (sep := .str S_MT)))
    else pure v)]

partial def checkPlacement (modes : Nat) (ijname : String) (parenttypes : Nat)
    (inj : InjId) : SIO Bool := do
  let d ← getInj inj
  let modenum := d.mode
  if (modes &&& modenum) == 0 then do
    let allowed := [M_KEYPRE, M_KEYPOST, M_VAL].filter (fun m => (modes &&& m) != 0)
    let placements := String.intercalate ","
      (allowed.map (fun m => if m == M_VAL then "value" else "key"))
    let cur := if modenum == M_VAL then "value" else "key"
    pushErr inj ("$" ++ ijname ++ ": invalid placement as " ++ cur
      ++ ", expected: " ++ placements ++ ".")
    pure false
  else if !(← isempty (vInt parenttypes)) then do
    let ptype := typify d.parent
    if (parenttypes &&& ptype) == 0 then do
      pushErr inj ("$" ++ ijname ++ ": invalid placement in parent "
        ++ typename (ptype : Int) ++ ", expected: " ++ typename (parenttypes : Int) ++ ".")
      pure false
    else pure true
  else pure true

partial def injectorArgs (argtypes : List Nat) (args : Value) : SIO (List Value) := do
  let numargs := argtypes.length
  let foundRef ← IO.mkRef (Array.replicate (1 + numargs) Value.noval)
  let mut argi : Nat := 0
  let mut stop := false
  for at_ in argtypes do
    if !stop then
      let arg ← getelem args (vInt (argi : Int))
      let argtype := typify arg
      if (at_ &&& argtype) == 0 then do
        let msg := "invalid argument: " ++ (← stringify arg (maxlen := .num 22.0))
          ++ " (" ++ typename (argtype : Int) ++ " at position " ++ toString (1 + argi)
          ++ ") is not of type: " ++ typename (at_ : Int) ++ "."
        foundRef.modify (fun a => a.set! 0 (Value.str msg))
        stop := true
      else
        foundRef.modify (fun a => a.set! (1 + argi) arg)
    argi := argi + 1
  pure (← foundRef.get).toList

partial def injectChild (child : Value) (store : Value) (inj : InjId) : SIO InjId := do
  let d ← getInj inj
  let cinjRef ← IO.mkRef inj
  (match d.prior with
   | some prior => do
     let pd ← getInj prior
     (match pd.prior with
      | some pprior => do
        let c ← makeChildInj pprior pd.keyi pd.keys
        modInj c (fun dd => { dd with ival := child })
        let _ ← setprop (← getInj c).parent pd.key child
        cinjRef.set c
      | none => do
        let c ← makeChildInj prior d.keyi d.keys
        modInj c (fun dd => { dd with ival := child })
        let _ ← setprop (← getInj c).parent d.key child
        cinjRef.set c)
   | none => pure ())
  let cinj ← cinjRef.get
  let _ ← inject child store (.iinj cinj)
  pure cinj

partial def transformFormat : InjectorFn := fun inj _v _ref store => do
  let d0 ← getInj inj
  let _ ← slice d0.keys (start := .num 0.0) (stop := .num 1.0) (mutate := true)
  if d0.mode != M_VAL then pure .noval
  else do
    let d ← getInj inj
    let name ← lookupRaw d.parent (.num 1.0)
    let child ← lookupRaw d.parent (.num 2.0)
    let tkey ← getelem d.path (.num (-2.0))
    let target ← do
      let t ← getelem d.nodes (.num (-2.0))
      if isNullish t then getelem d.nodes (.num (-1.0)) else pure t
    let cinj ← injectChild child store inj
    let resolved := (← getInj cinj).ival
    let formatter : Option (Value → Value → SIO Value) ←
      if (T_FUNCTION &&& typify name) > 0 then
        match name with
        | .func fid => pure (some (fun k v => do
            callFunc fid (← getDummyInj) v (← jsString k) .noval))
        | _ => pure none
      else do
        let nm ← jsString name
        pure ((formatterTbl.find? (·.1 == nm)).map (·.2))
    match formatter with
    | none => do
      pushErr inj ("$FORMAT: unknown format: " ++ (← jsString name) ++ ".")
      pure .noval
    | some f => do
      let out ← walk resolved (before := some (fun k v _p _path => f k v))
      let _ ← setprop target tkey out
      pure out

partial def transformApply : InjectorFn := fun inj _v _ref store => do
  if !(← checkPlacement M_VAL "APPLY" T_LIST inj) then pure .noval
  else do
    let d ← getInj inj
    let args ← slice d.parent (start := .num 1.0)
    let res ← injectorArgs [T_FUNCTION, T_ANY] args
    let err := res.getD 0 .noval
    let applyFn := res.getD 1 .noval
    let child := res.getD 2 .noval
    if !(isNoval err) then do
      pushErr inj ("$APPLY: " ++ (← jsString err))
      pure .noval
    else do
      let tkey ← getelem d.path (.num (-2.0))
      let target ← do
        let t ← getelem d.nodes (.num (-2.0))
        if isNullish t then getelem d.nodes (.num (-1.0)) else pure t
      let cinj ← injectChild child store inj
      let resolved := (← getInj cinj).ival
      let out ← match applyFn with
        | .func fid => callFunc fid cinj resolved "" store
        | _ => pure Value.noval
      let _ ← setprop target tkey out
      pure out

-- ---------------------------------------------------------------------------
-- transform
-- ---------------------------------------------------------------------------

partial def transform (data spec : Value) (inj : InjArg := .inone) : SIO Value := do
  let origspec := spec
  let spec ← clone spec
  let extra := match inj with
    | .idef d => d.dExtra
    | _ => .noval
  let collect := match inj with
    | .idef d => !(isNoval d.dErrs)
    | _ => false
  let errs ← match inj with
    | .idef d => if collect then pure d.dErrs else emptyList
    | _ => emptyList
  let extraTransforms ← emptyMap
  let extraData ← emptyMap
  if !(isNoval extra) then
    for (k, v) in (← itemsPairs extra) do
      if k.startsWith S_DS then
        let _ ← setprop extraTransforms (.str k) v
      else
        let _ ← setprop extraData (.str k) v
  let edPart ← if (← isempty extraData) then pure Value.noval else clone extraData
  let dataClone ← merge (← newList #[edPart, ← clone data])
  let store ← emptyMap
  let put (k : String) (v : Value) : SIO Unit := do
    let _ ← setprop store (.str k) v
  put S_DTOP dataClone
  put S_DSPEC (← vFunc (fun _ _ _ _ => pure origspec))
  put "$BT" (← vFunc (fun _ _ _ _ => pure (.str S_BT)))
  put "$DS" (← vFunc (fun _ _ _ _ => pure (.str S_DS)))
  put "$WHEN" (← vFunc (fun _ _ _ _ => pure (.str "1970-01-01T00:00:00.000Z")))
  put "$DELETE" (← vFunc transformDelete)
  put "$COPY" (← vFunc transformCopy)
  put "$KEY" (← vFunc transformKey)
  put "$ANNO" (← vFunc transformAnno)
  put "$MERGE" (← vFunc transformMerge)
  put "$EACH" (← vFunc transformEach)
  put "$PACK" (← vFunc transformPack)
  put "$REF" (← vFunc transformRef)
  put "$FORMAT" (← vFunc transformFormat)
  put "$APPLY" (← vFunc transformApply)
  for (k, v) in (← itemsPairs extraTransforms) do
    put k v
  put S_DERRS errs
  let idef0 : InjDef := { dErrs := errs }
  let idef := match inj with
    | .idef d => { idef0 with
        dMeta := d.dMeta, dModify := d.dModify,
        dHandler := d.dHandler, dBase := d.dBase }
    | _ => idef0
  let out ← inject spec store (.idef idef)
  if (← size errs) > 0 && !collect then
    throw (IO.userError (← join errs (sep := .str " | ")))
  pure out

-- ---------------------------------------------------------------------------
-- validate
-- ---------------------------------------------------------------------------

partial def invalidTypeMsg (path : Value) (needtype : String) (vt : Int) (v : Value) :
    SIO String := do
  let vs ← if isNullish v then pure "no value" else stringify v
  let fieldPart ← if (← size path) > 1 then do
      pure ("field " ++ (← pathify path (startin := .num 1.0)) ++ " to be ")
    else pure ""
  let typePart := if !(isNullish v) then typename vt ++ S_VIZ else ""
  return "Expected " ++ fieldPart ++ needtype ++ ", but found " ++ typePart ++ vs ++ "."

partial def validateString : InjectorFn := fun inj _v _ref _store => do
  let d ← getInj inj
  let out ← lookupRaw d.dparent d.key
  let t := typify out
  if (T_STRING &&& t) == 0 then do
    pushErr inj (← invalidTypeMsg d.path S_STRING (t : Int) out)
    pure .noval
  else if out == .str S_MT then do
    pushErr inj ("Empty string at " ++ (← pathify d.path (startin := .num 1.0)))
    pure .noval
  else pure out

partial def validateType : InjectorFn := fun inj _v refstr _store => do
  let d ← getInj inj
  let tname := if refstr.length > 1 then (strDrop refstr 1).toLower else "any"
  let idx : Int := Id.run do
    let mut r : Int := -1
    for i in [0:typenameTbl.size] do
      if typenameTbl[i]! == tname && r < 0 then r := i
    return r
  let typev0 : Nat := if idx >= 0 then 1 <<< (31 - idx.toNat) else 0
  let typev := if tname == S_NIL then typev0 ||| T_NULL else typev0
  let out ← lookupRaw d.dparent d.key
  let t := typify out
  if (t &&& typev) == 0 then do
    pushErr inj (← invalidTypeMsg d.path tname (t : Int) out)
    pure .noval
  else pure out

partial def validateAny : InjectorFn := fun inj _v _ref _store => do
  let d ← getInj inj
  lookupRaw d.dparent d.key

partial def validateChild : InjectorFn := fun inj _v _ref _store => do
  let d ← getInj inj
  let parent := d.parent
  let key := d.key
  let path := d.path
  let keys := d.keys
  if d.mode == M_KEYPRE then do
    let childtm ← getprop parent key
    let pkey ← getelem path (.num (-2.0))
    let tval ← getprop d.dparent pkey
    if isNoval tval then do
      let _ ← delprop parent key
      pure .noval
    else if !(ismap tval) then do
      let psize ← size path
      let ppath ← slice path (start := .num 0.0) (stop := vInt (psize - 1))
      pushErr inj (← invalidTypeMsg ppath S_OBJECT ((typify tval : Nat) : Int) tval)
      pure .noval
    else do
      for ckey in (← keysof tval) do
        let _ ← setprop parent (.str ckey) (← clone childtm)
        let n ← size keys
        let _ ← setprop keys (vInt n) (.str ckey)
      let _ ← delprop parent key
      pure .noval
  else if d.mode == M_VAL then do
    let childtm ← getprop parent (.num 1.0)
    if !(islist parent) then do
      pushErr inj "Invalid $CHILD as value"
      pure .noval
    else if isNoval d.dparent then do
      (match parent with
       | .list r => setListItems r #[]
       | _ => pure ())
      pure .noval
    else if !(islist d.dparent) then do
      let psize ← size path
      let ppath ← slice path (start := .num 0.0) (stop := vInt (psize - 1))
      pushErr inj (← invalidTypeMsg ppath S_LIST ((typify d.dparent : Nat) : Int) d.dparent)
      let np ← size parent
      modInj inj (fun dd => { dd with keyi := np })
      pure d.dparent
    else do
      for (k, _) in (← itemsPairs d.dparent) do
        let _ ← setprop parent (.str k) (← clone childtm)
      (match parent with
       | .list r => do
         let n ← size d.dparent
         let xs ← listItems r
         setListItems r (xs.extract 0 (min n.toNat xs.size))
       | _ => pure ())
      modInj inj (fun dd => { dd with keyi := 0 })
      getprop d.dparent (.num 0.0)
  else pure .noval

/-- Deep structural equality (validate $EXACT). -/
partial def veq (a b : Value) : SIO Bool := do
  match a, b with
  | .noval, .noval => pure true
  | .null, .null => pure true
  | .bool x, .bool y => pure (x == y)
  | .num x, .num y => pure (x == y)
  | .str x, .str y => pure (x == y)
  | .sentinel x, .sentinel y => pure (x == y)
  | .list x, .list y => do
    let xs ← listItems x
    let ys ← listItems y
    if xs.size != ys.size then pure false
    else do
      for i in [0:xs.size] do
        if !(← veq xs[i]! ys[i]!) then return false
      pure true
  | .map x, .map y => do
    let xes ← mapEntries x
    let yes ← mapEntries y
    if xes.size != yes.size then pure false
    else do
      for (k, v) in xes do
        match omapGet yes k with
        | some w =>
          if !(← veq v w) then return false
        | none => return false
      pure true
  | _, _ => pure false

partial def validateExact : InjectorFn := fun inj _v _ref _store => do
  let d ← getInj inj
  if d.mode == M_VAL then do
    let parent := d.parent
    if !(islist parent) || d.keyi != 0 then do
      pushErr inj ("The $EXACT validator at field "
        ++ (← pathify d.path (startin := .num 1.0) (endin := .num 1.0))
        ++ " must be the first element of an array.")
      pure .noval
    else do
      let nk ← size d.keys
      modInj inj (fun dd => { dd with keyi := nk })
      injSetval inj d.dparent (ancestor := 2)
      let psize ← size d.path
      let npath ← slice d.path (start := .num 0.0) (stop := vInt (psize - 1))
      let nkey ← getelem npath (.num (-1.0))
      modInj inj (fun dd => { dd with path := npath, key := nkey })
      let tvals ← slice parent (start := .num 1.0)
      if (← size tvals) == 0 then do
        let d2 ← getInj inj
        pushErr inj ("The $EXACT validator at field "
          ++ (← pathify d2.path (startin := .num 1.0) (endin := .num 1.0))
          ++ " must have at least one argument.")
        pure .noval
      else do
        let mut matched := false
        for tval in (← listItemsOf tvals) do
          if !matched && (← veq tval d.dparent) then matched := true
        if !matched then do
          let d2 ← getInj inj
          let mut descs : List String := []
          for (_, x) in (← itemsPairs tvals) do
            descs := (← stringify x) :: descs
          let valdesc := replaceTransformNames (String.intercalate ", " descs.reverse)
          let ntv ← size tvals
          pushErr inj (← invalidTypeMsg d2.path
            ((if (← size d2.path) > 1 then "" else "value ")
              ++ "exactly equal to " ++ (if ntv == 1 then "" else "one of ") ++ valdesc)
            ((typify d.dparent : Nat) : Int) d.dparent)
        pure .noval
  else do
    let _ ← delprop d.parent d.key
    pure .noval

/-- The validate modify callback: structural checks at each node. -/
partial def validation : ModifyFn := fun pval key parent inj => do
  if isSkip pval then pure ()
  else do
    let d ← getInj inj
    let exact ← getprop d.imeta (.str S_BEXACT) (.bool false)
    let cval ← getprop d.dparent key
    let exactB := exact == .bool true
    if !exactB && isNoval cval then pure ()
    else do
      let ptype := typify pval
      if (T_STRING &&& ptype) > 0 && strContains (← jsString pval) '$' then pure ()
      else do
        let ctype := typify cval
        if ptype != ctype && !(isNoval pval) then
          pushErr inj (← invalidTypeMsg d.path (typename (ptype : Int)) (ctype : Int) cval)
        else if ismap cval then do
          if !(ismap pval) then
            pushErr inj (← invalidTypeMsg d.path (typename (ptype : Int)) (ctype : Int) cval)
          else do
            let ckeys ← keysof cval
            let pkeys ← keysof pval
            let bopen ← getprop pval (.str S_BOPEN)
            if pkeys.size > 0 && !(bopen == .bool true) then do
              let mut badkeys : List String := []
              for ck in ckeys do
                if isNoval (← lookupRaw pval (.str ck)) then badkeys := ck :: badkeys
              if badkeys.length > 0 then
                pushErr inj ("Unexpected keys at field "
                  ++ (← pathify d.path (startin := .num 1.0)) ++ S_VIZ
                  ++ String.intercalate ", " badkeys.reverse)
            else do
              let _ ← merge (← newList #[pval, cval])
              if isnode pval then
                let _ ← delprop pval (.str S_BOPEN)
        else if islist cval then do
          if !(islist pval) then
            pushErr inj (← invalidTypeMsg d.path (typename (ptype : Int)) (ctype : Int) cval)
        else if exactB then do
          if !(← veq cval pval) then do
            let pathmsg ← if (← size d.path) > 1 then do
                pure ("at field " ++ (← pathify d.path (startin := .num 1.0)) ++ ": ")
              else pure ""
            pushErr inj ("Value " ++ pathmsg ++ (← jsString cval)
              ++ " should equal " ++ (← jsString pval) ++ ".")
        else
          let _ ← setprop parent key cval

partial def validateHandler : InjectorFn := fun inj v refstr store => do
  match metaPathMatch refstr with
  | some (_, g2, _) => do
    if g2 == "=" then
      injSetval inj (← newList #[.str S_BEXACT, v])
    else
      injSetval inj v
    modInj inj (fun dd => { dd with keyi := -1 })
    pure SKIP
  | none => injectHandler inj v refstr store

mutual

partial def validateOne : InjectorFn := fun inj _v _ref store => do
  let d ← getInj inj
  if d.mode == M_VAL then do
    let parent := d.parent
    if !(islist parent) || d.keyi != 0 then do
      pushErr inj ("The $ONE validator at field "
        ++ (← pathify d.path (startin := .num 1.0) (endin := .num 1.0))
        ++ " must be the first element of an array.")
      pure .noval
    else do
      let nk ← size d.keys
      modInj inj (fun dd => { dd with keyi := nk })
      injSetval inj d.dparent (ancestor := 2)
      let psize ← size d.path
      let npath ← slice d.path (start := .num 0.0) (stop := vInt (psize - 1))
      let nkey ← getelem npath (.num (-1.0))
      modInj inj (fun dd => { dd with path := npath, key := nkey })
      let tvals ← slice parent (start := .num 1.0)
      if (← size tvals) == 0 then do
        let d2 ← getInj inj
        pushErr inj ("The $ONE validator at field "
          ++ (← pathify d2.path (startin := .num 1.0) (endin := .num 1.0))
          ++ " must have at least one argument.")
        pure .noval
      else do
        let mut matched := false
        for tval in (← listItemsOf tvals) do
          if !matched then do
            let terrs ← emptyList
            let em ← emptyMap
            let vstore ← merge (← newList #[em, store]) (maxdepth := .num 1.0)
            let _ ← setprop vstore (.str S_DTOP) d.dparent
            let idef : InjDef := { dExtra := vstore, dErrs := terrs, dMeta := d.imeta }
            let vcurrent ← validate d.dparent tval (.idef idef)
            injSetval inj vcurrent (ancestor := -2)
            if (← size terrs) == 0 then matched := true
        if !matched then do
          let d2 ← getInj inj
          let mut descs : List String := []
          for (_, x) in (← itemsPairs tvals) do
            descs := (← stringify x) :: descs
          let valdesc := replaceTransformNames (String.intercalate ", " descs.reverse)
          let ntv ← size tvals
          pushErr inj (← invalidTypeMsg d2.path
            ((if ntv > 1 then "one of " else "") ++ valdesc)
            ((typify d.dparent : Nat) : Int) d.dparent)
        pure .noval
  else pure .noval

partial def validate (data spec : Value) (inj : InjArg := .inone) : SIO Value := do
  let extra := match inj with
    | .idef d => d.dExtra
    | _ => .noval
  let collect := match inj with
    | .idef d => !(isNoval d.dErrs)
    | _ => false
  let errs ← match inj with
    | .idef d => if collect then pure d.dErrs else emptyList
    | _ => emptyList
  let base ← emptyMap
  let put (k : String) (v : Value) : SIO Unit := do
    let _ ← setprop base (.str k) v
  for k in ["$DELETE", "$COPY", "$KEY", "$META", "$MERGE", "$EACH", "$PACK"] do
    put k .null
  put "$STRING" (← vFunc validateString)
  for k in ["$NUMBER", "$INTEGER", "$DECIMAL", "$BOOLEAN", "$NULL", "$NIL",
            "$MAP", "$LIST", "$FUNCTION", "$INSTANCE"] do
    put k (← vFunc validateType)
  put "$ANY" (← vFunc validateAny)
  put "$CHILD" (← vFunc validateChild)
  put "$ONE" (← vFunc validateOne)
  put "$EXACT" (← vFunc validateExact)
  let extraV ← if isNoval extra then emptyMap else pure extra
  let errsWrap ← newMap #[(S_DERRS, errs)]
  let store ← merge (← newList #[base, extraV, errsWrap]) (maxdepth := .num 1.0)
  let meta0 ← match inj with
    | .idef d => if !(isNoval d.dMeta) then pure d.dMeta else emptyMap
    | _ => emptyMap
  let bexact ← getprop meta0 (.str S_BEXACT) (.bool false)
  let _ ← setprop meta0 (.str S_BEXACT) bexact
  let modId ← registerModify validation
  let handlerId ← registerFunc validateHandler
  let idef : InjDef := { dMeta := meta0, dExtra := store, dModify := some modId,
                         dHandler := some handlerId, dErrs := errs }
  let out ← transform data spec (.idef idef)
  if (← size errs) > 0 && !collect then
    throw (IO.userError (← join errs (sep := .str " | ")))
  pure out

end

-- ---------------------------------------------------------------------------
-- select
-- ---------------------------------------------------------------------------

partial def selectAnd : InjectorFn := fun inj _v _ref store => do
  let d ← getInj inj
  if d.mode == M_KEYPRE then do
    let terms ← getprop d.parent d.key
    let ppath ← slice d.path (start := .num (-1.0))
    let point ← getpath store ppath
    let em ← emptyMap
    let vstore ← merge (← newList #[em, store]) (maxdepth := .num 1.0)
    let _ ← setprop vstore (.str S_DTOP) point
    for (_, term) in (← itemsPairs terms) do
      let terrs ← emptyList
      let idef : InjDef := { dExtra := vstore, dErrs := terrs, dMeta := d.imeta }
      let _ ← validate point term (.idef idef)
      if (← size terrs) != 0 then
        pushErr inj ("AND:" ++ (← pathify ppath) ++ "⨯" ++ (← stringify point)
          ++ " fail:" ++ (← stringify terms))
    let gkey ← getelem d.path (.num (-2.0))
    let gp ← getelem d.nodes (.num (-2.0))
    let _ ← setprop gp gkey point
    pure .noval
  else pure .noval

partial def selectOr : InjectorFn := fun inj _v _ref store => do
  let d ← getInj inj
  if d.mode == M_KEYPRE then do
    let terms ← getprop d.parent d.key
    let ppath ← slice d.path (start := .num (-1.0))
    let point ← getpath store ppath
    let em ← emptyMap
    let vstore ← merge (← newList #[em, store]) (maxdepth := .num 1.0)
    let _ ← setprop vstore (.str S_DTOP) point
    let mut done := false
    for (_, term) in (← itemsPairs terms) do
      if !done then do
        let terrs ← emptyList
        let idef : InjDef := { dExtra := vstore, dErrs := terrs, dMeta := d.imeta }
        let _ ← validate point term (.idef idef)
        if (← size terrs) == 0 then do
          let gkey ← getelem d.path (.num (-2.0))
          let gp ← getelem d.nodes (.num (-2.0))
          let _ ← setprop gp gkey point
          done := true
    if !done then
      pushErr inj ("OR:" ++ (← pathify ppath) ++ "⨯" ++ (← stringify point)
        ++ " fail:" ++ (← stringify terms))
    pure .noval
  else pure .noval

partial def selectNot : InjectorFn := fun inj _v _ref store => do
  let d ← getInj inj
  if d.mode == M_KEYPRE then do
    let term ← getprop d.parent d.key
    let ppath ← slice d.path (start := .num (-1.0))
    let point ← getpath store ppath
    let em ← emptyMap
    let vstore ← merge (← newList #[em, store]) (maxdepth := .num 1.0)
    let _ ← setprop vstore (.str S_DTOP) point
    let terrs ← emptyList
    let idef : InjDef := { dExtra := vstore, dErrs := terrs, dMeta := d.imeta }
    let _ ← validate point term (.idef idef)
    if (← size terrs) == 0 then
      pushErr inj ("NOT:" ++ (← pathify ppath) ++ "⨯" ++ (← stringify point)
        ++ " fail:" ++ (← stringify term))
    let gkey ← getelem d.path (.num (-2.0))
    let gp ← getelem d.nodes (.num (-2.0))
    let _ ← setprop gp gkey point
    pure .noval
  else pure .noval

def numCmp (a b : Value) (op : String) : Bool :=
  match a, b with
  | .num x, .num y =>
    match op with
    | "$GT" => x > y
    | "$LT" => x < y
    | "$GTE" => x >= y
    | "$LTE" => x <= y
    | _ => false
  | _, _ => false

partial def selectCmp : InjectorFn := fun inj _v refstr store => do
  let d ← getInj inj
  if d.mode == M_KEYPRE then do
    let term ← getprop d.parent d.key
    let gkey ← getelem d.path (.num (-2.0))
    let ppath ← slice d.path (start := .num (-1.0))
    let point ← getpath store ppath
    let pass ←
      if refstr == "$GT" || refstr == "$LT" || refstr == "$GTE" || refstr == "$LTE" then
        pure (numCmp point term refstr)
      else if refstr == "$LIKE" then
        match term with
        | .str t => pure (Vregex.testStr t (← stringify point))
        | _ => pure false
      else pure false
    if pass then do
      let gp ← getelem d.nodes (.num (-2.0))
      let _ ← setprop gp gkey point
    else
      pushErr inj ("CMP: " ++ (← pathify ppath) ++ "⨯" ++ (← stringify point)
        ++ " fail:" ++ refstr ++ " " ++ (← stringify term))
    pure .noval
  else pure .noval

partial def select (children query : Value) : SIO Value := do
  if !(isnode children) then emptyList
  else do
    let children ←
      if ismap children then do
        let mut arr : Array Value := #[]
        for (k, n) in (← itemsPairs children) do
          let _ ← setprop n (.str S_DKEY) (.str k)
          arr := arr.push n
        newList arr
      else do
        let xs ← listItemsOf children
        let mut arr : Array Value := #[]
        for i in [0:xs.size] do
          let n := xs[i]!
          if ismap n then
            let _ ← setprop n (.str S_DKEY) (vInt i)
          arr := arr.push n
        newList arr
    let results ← emptyList
    let extra ← emptyMap
    let _ ← setprop extra (.str "$AND") (← vFunc selectAnd)
    let _ ← setprop extra (.str "$OR") (← vFunc selectOr)
    let _ ← setprop extra (.str "$NOT") (← vFunc selectNot)
    for k in ["$GT", "$LT", "$GTE", "$LTE", "$LIKE"] do
      let _ ← setprop extra (.str k) (← vFunc selectCmp)
    let q ← clone query
    let _ ← walk q (before := some (fun _k v _p _path => do
      if ismap v then do
        let cur ← getprop v (.str S_BOPEN) (.bool true)
        let _ ← setprop v (.str S_BOPEN) cur
        pure v
      else pure v))
    for child in (← listItemsOf children) do
      let errs ← emptyList
      let m ← emptyMap
      let _ ← setprop m (.str S_BEXACT) (.bool true)
      let idef : InjDef := { dErrs := errs, dMeta := m, dExtra := extra }
      let _ ← validate child (← clone q) (.idef idef)
      if (← size errs) == 0 then do
        let n ← size results
        let _ ← setprop results (vInt n) child
    pure results

-- ---------------------------------------------------------------------------
-- builders
-- ---------------------------------------------------------------------------

partial def jm (kv : List Value) : SIO Value := do
  let m ← emptyMap
  let arr := kv.toArray
  let n := arr.size
  let mut i := 0
  while i < n do
    let k0 := arr[i]!
    let k ← match k0 with
      | .null => pure "null"
      | .str s => pure s
      | _ => stringify k0
    let v := if i + 1 < n then arr[i + 1]! else Value.null
    (match m with
     | .map mid => mapSetKV mid k v
     | _ => pure ())
    i := i + 2
  pure m

def jt (v : List Value) : SIO Value := newList v.toArray

def tn (t : Int) : String := typename t

-- ---------------------------------------------------------------------------
-- Finish: register the default handler and the dummy inj used by the
-- (corpus-unreached) getelem function-alt path.
-- ---------------------------------------------------------------------------

/-- Create a fresh library context: empty heaps plus the default handler and
    the dummy inj used by the (corpus-unreached) getelem function-alt path. -/
def mkCtx : IO Ctx := do
  let ctx : Ctx := {
    valueHeap := ← IO.mkRef #[], funcReg := ← IO.mkRef #[],
    modifyReg := ← IO.mkRef #[], injHeap := ← IO.mkRef #[],
    dummyInj := ← IO.mkRef none, injectHandlerFid := ← IO.mkRef 0 }
  let setup : SIO Unit := do
    let fid ← registerFunc injectHandler
    (← read).injectHandlerFid.set fid
    let parent ← newMap #[(S_DTOP, Value.noval)]
    let di ← newInj .noval parent
    (← read).dummyInj.set (some di)
  setup.run ctx
  pure ctx

end VoxgigStruct
