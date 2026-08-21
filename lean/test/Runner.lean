/- The shared corpus, run on the shared runner.

   The in-situ runner - a JSON reader, `fixJson`, `eqv`, `matchval`,
   `doMatch`, `resolveArgs`, `checkResult` and `handleError`, all of it this
   port's own copy of omni's algorithm - is gone. Every group is driven
   through voxgig/omni, so this file only says WHICH subject answers each
   group and with which flags.

   omni is consumed as a local checkout: the Makefile copies `Omni.lean` into
   `.omni-build/`, which `lakefile.toml` declares as a lean_lib the RUNNER
   depends on. `lake build VoxgigStruct` compiles the library alone, and
   nothing shipped names omni (register 4.13).

   Flags mirror canonical: typescript/test/utility/StructUtility.test.ts. -/

import VoxgigStruct
import Omni

open VoxgigStruct

def nullmark : String := "__NULL__"

-- ---------------- the bridge ----------------

/-- omni's runner is PURE (`Except String Unit`); this port's library runs in
`IO`, because its node heap is a set of `IO.Ref`s. The subject callback is the
one place the two meet, so it runs the action with `unsafeIO` - the escape
hatch Lean provides for exactly this. Test code only: nothing in `src/` uses
it. -/
unsafe def runsioImpl {α : Type} [Inhabited α] (ctx : Ctx) (act : SIO α)
    : Except String α :=
  match unsafeIO (act.run ctx) with
  | .ok value => .ok value
  | .error err => .error err.toString

@[implemented_by runsioImpl]
opaque runsio {α : Type} [Inhabited α] (ctx : Ctx) (act : SIO α) : Except String α

/-- omni's model -> this port's. Both draw the same absent/null distinction
(`.noval` is canonical `undefined`), so nothing is guessed. Nodes are built
through `newList` / `emptyMap`, so what a subject receives is a real heap node
it may rewrite in place. -/
partial def tostruct (value : Omni.Val) : SIO Value := do
  match value with
  | none => pure .noval
  | some .null => pure .null
  | some (.bool b) => pure (.bool b)
  | some (.num n) => pure (.num n.toFloat)
  | some (.str t) => pure (.str t)
  | some (.arr entries) => do
    let mut out : Array Value := #[]
    for entry in entries do
      out := out.push (← tostruct (some entry))
    newList out
  | some (.obj kvs) => do
    let m ← emptyMap
    for kv in kvs.toArray do
      let _ ← setprop m (.str kv.1) (← tostruct (some kv.2))
    pure m

/-- This port's model -> omni's. A function or a sentinel has no JSON form and
omni only ever stringifies one, so it becomes its own rendering rather than
silently collapsing to null. -/
partial def toomni (value : Value) : SIO Omni.Val := do
  match value with
  | .noval => pure none
  | .null => pure (some Lean.Json.null)
  | .bool b => pure (some (Lean.Json.bool b))
  | .num n => pure (some (
      -- Whole values keep their integer spelling; anything else goes through
      -- the float constructor, which is the only lossless route Lean offers.
      if n == n.floor && n.abs < 9007199254740992.0 then
        Lean.Json.num (Lean.JsonNumber.fromInt (Int.ofNat n.abs.toUInt64.toNat
          |> fun m => if n < 0.0 then -m else m))
      else
        match Lean.JsonNumber.fromFloat? n with
        | .inr number => Lean.Json.num number
        | .inl _ => Lean.Json.null))
  | .str t => pure (some (Lean.Json.str t))
  | .list id => do
    let mut out : Array Lean.Json := #[]
    for item in (← listItems id) do
      out := out.push ((← toomni item).getD Lean.Json.null)
    pure (some (Lean.Json.arr out))
  | .map id => do
    let mut out : List (String × Lean.Json) := []
    for (k, v) in (← mapEntries id) do
      out := (k, (← toomni v).getD Lean.Json.null) :: out
    pure (some (Lean.Json.mkObj out.reverse))
  | .func _ => pure (some (Lean.Json.str "[Function]"))
  | .sentinel tag => pure (some (Lean.Json.str ("`$" ++ tag ++ "`")))

/-- Order-independent deep equality, through omni's own rule so the
hand-written comparisons below match the way every group is checked. -/
def eqv (a b : Value) : SIO Bool := do
  pure (Omni.deepequal (← toomni a) (← toomni b))

-- ---------------- result tracking ----------------

initialize npass : IO.Ref Nat ← IO.mkRef 0
initialize nfail : IO.Ref Nat ← IO.mkRef 0
initialize failures : IO.Ref (List String) ← IO.mkRef []

def record (group : String) (ok : Bool) (msg : String) : IO Unit := do
  if ok then npass.modify (· + 1)
  else do
    nfail.modify (· + 1)
    failures.modify (("FAIL " ++ group ++ " - " ++ msg) :: ·)

def omapV (kvs : List (String × Value)) : SIO Value := do
  let m ← emptyMap
  for (k, v) in kvs do
    let _ ← setprop m (.str k) v
  pure m

def getpropRawPub (e : Value) (k : String) : SIO Value := do
  match e with
  | .map id => pure ((omapGet (← mapEntries id) k).getD .noval)
  | _ => pure .noval

-- ---------------- running a group ----------------

initialize runpack : IO.Ref (Option Omni.RunPack) ← IO.mkRef none

/-- Each group is one assertion: omni stops at its first failing entry and
reports the index, the entry and both values.

The subject is handed omni's arguments converted into this port's heap nodes,
and hands the converted arguments BACK - `match.args` asserts an in-place
rewrite in eight of `minor/setpath`'s nine entries and all six of
`merge/integrity`, and Lean is pure, so nothing this port does to a node is
visible through omni's argument list. rust, cpp, ocaml, elixir, haskell,
clojure, scala and swift needed the same entry point for the same reason. -/
def runSet (group : String) (node : Value) (subject : List Value → SIO Value)
    (flagNull : Bool := true) : SIO Unit := do
  let ctx ← read
  let pack ← match (← runpack.get) with
    | some pack => pure pack
    | none => throw (IO.userError "runner not started")
  let spec := (← toomni node).getD Lean.Json.null
  let call : Omni.SubjectArgs := fun cells =>
    runsio ctx (do
      let mut built : List Value := []
      for cell in cells do
        built := (← tostruct cell) :: built
      let args := built.reverse
      let res ← subject args
      let mut back : List Omni.Val := []
      for arg in args do
        back := (← toomni arg) :: back
      pure (back.reverse, ← toomni res))
  match pack.runsetflagsargs spec { null := flagNull, name := some group } call with
  | .ok () => record group true ""
  | .error message => record group false message

/-- `merge.basic`, `inject.basic` and `transform.basic` are single entries, not
sets, so the runner cannot drive them. Compared here, through omni's own
deepequal so the rule is the one every group uses. -/
def runSingle (group : String) (node : Value) (actualFn : Value → SIO Value) : SIO Unit := do
  try
    let expected ← getpropRawPub node "out"
    let actual ← actualFn (← getpropRawPub node "in")
    if ← eqv expected actual then record group true ""
    else
      record group false
        ("Expected: " ++ (← stringify expected) ++ ", got: " ++ (← stringify actual))
  catch e => record group false e.toString

-- ---------------- arg helpers ----------------

def arg1 (f : Value → SIO Value) : List Value → SIO Value :=
  fun args => f (args.headD .noval)

def vget (vin : Value) (k : String) : SIO Value := do
  match vin with
  | .map id => pure ((omapGet (← mapEntries id) k).getD .noval)
  | _ => pure .noval

def vhas (vin : Value) (k : String) : SIO Bool := do
  match vin with
  | .map id => pure (omapHas (← mapEntries id) k)
  | _ => pure false

-- ---------------- test groups ----------------

def nullModifier : ModifyFn := fun v key parent _inj => do
  if v == .str nullmark then
    let _ ← setprop parent key .null
  else match v with
    | .str s =>
      let _ ← setprop parent key (.str (s.replace nullmark "null"))
    | _ => pure ()

def runWalkLog (group : String) (node : Value) : SIO Unit := do
  try
    let testData ← clone node
    let log ← emptyList
    let walklog : WalkFn := fun key v parent path => do
      let ks ← if isNullish key then stringify .noval else stringify key
      let vs ← stringify v
      let ps ← if isNullish parent then stringify .noval else stringify parent
      let ts ← pathify path
      let n ← size log
      let _ ← setprop log (vInt n)
        (.str ("k=" ++ ks ++ ", v=" ++ vs ++ ", p=" ++ ps ++ ", t=" ++ ts))
      pure v
    let _ ← walk (← getpropRawPub testData "in") (after := some walklog)
    let expected ← getprop (← getpropRawPub testData "out") (.str "after")
    if ← eqv expected log then record group true ""
    else
      record group false
        ("Expected: " ++ (← stringify expected) ++ ", got: " ++ (← stringify log))
  catch e => record group false e.toString

def walkCopySubject (vin : Value) : SIO Value := do
  let cur ← IO.mkRef (← newList #[.noval])
  let walkcopy : WalkFn := fun key v _parent path => do
    if isNullish key then do
      let seed ← if ismap v then emptyMap else if islist v then emptyList else pure v
      cur.set (← newList #[seed])
      pure v
    else do
      let i ← size path
      let iN := i.toNat
      let nv ← if isnode v then do
          match (← cur.get) with
          | .list r => do
            let mut xs ← listItems r
            while xs.size <= iN do
              xs := xs.push .noval
            let n ← if ismap v then emptyMap else emptyList
            xs := xs.set! iN n
            setListItems r xs
            pure n
          | _ => pure v
        else pure v
      let tgt ← getelem (← cur.get) (vInt (i - 1))
      let _ ← setprop tgt key nv
      pure v
  let _ ← walk vin (before := some walkcopy)
  getelem (← cur.get) (.num 0.0)

def walkDepthSubject (vin : Value) : SIO Value := do
  let top ← IO.mkRef Value.noval
  let curr ← IO.mkRef Value.noval
  let copy : WalkFn := fun key v _parent _path => do
    if isNullish key || isnode v then do
      let child ← if islist v then emptyList else emptyMap
      if isNullish key then do
        top.set child
        curr.set child
      else do
        let _ ← setprop (← curr.get) key child
        curr.set child
    else
      let _ ← setprop (← curr.get) key v
    pure v
  let _ ← walk (← vget vin "src") (before := some copy) (maxdepth := ← vget vin "maxdepth")
  top.get

def runAll (spec : Value) : SIO Unit := do
  let g := getpropRawPub spec
  let minor ← g "minor"
  let walks ← g "walk"
  let merges ← g "merge"
  let getpaths ← g "getpath"
  let injects ← g "inject"
  let transforms ← g "transform"
  let validates ← g "validate"
  let selects ← g "select"
  let sentinels ← g "sentinels"
  let mg := getpropRawPub minor

  -- minor
  runSet "minor.isnode" (← mg "isnode") (arg1 (fun v => pure (.bool (isnode v))))
  runSet "minor.ismap" (← mg "ismap") (arg1 (fun v => pure (.bool (ismap v))))
  runSet "minor.islist" (← mg "islist") (arg1 (fun v => pure (.bool (islist v))))
  runSet "minor.iskey" (← mg "iskey") (arg1 (fun v => pure (.bool (iskey v))))
    (flagNull := false)
  runSet "minor.strkey" (← mg "strkey") (arg1 (fun v => pure (.str (strkey v))))
    (flagNull := false)
  runSet "minor.isempty" (← mg "isempty") (arg1 (fun v => do pure (.bool (← isempty v))))
    (flagNull := false)
  runSet "minor.isfunc" (← mg "isfunc") (arg1 (fun v => pure (.bool (isfunc v))))
  runSet "minor.clone" (← mg "clone") (arg1 clone) (flagNull := false)
  runSet "minor.escre" (← mg "escre") (arg1 escre)
  runSet "minor.escurl" (← mg "escurl") (arg1 escurl)
  runSet "minor.stringify" (← mg "stringify")
    (arg1 (fun vin => do
      if ← vhas vin "val" then
        pure (.str (← stringify (← vget vin "val") (maxlen := ← vget vin "max")))
      else
        pure (.str (← stringify .noval))))
    (flagNull := false)
  runSet "minor.jsonify" (← mg "jsonify")
    (arg1 (fun vin => do
      pure (.str (← jsonify (← vget vin "val") (flags := ← vget vin "flags")))))
    (flagNull := false)
  runSet "minor.getelem" (← mg "getelem")
    (arg1 (fun vin => do
      let alt ← vget vin "alt"
      if isNullish alt then getelem (← vget vin "val") (← vget vin "key")
      else getelem (← vget vin "val") (← vget vin "key") alt))
    (flagNull := false)
  runSet "minor.delprop" (← mg "delprop")
    (arg1 (fun vin => do delprop (← vget vin "parent") (← vget vin "key")))
  runSet "minor.size" (← mg "size") (arg1 (fun v => do pure (vInt (← size v))))
    (flagNull := false)
  runSet "minor.slice" (← mg "slice")
    (arg1 (fun vin => do
      slice (← vget vin "val") (start := ← vget vin "start") (stop := ← vget vin "end")))
    (flagNull := false)
  runSet "minor.pad" (← mg "pad")
    (arg1 (fun vin => do
      pure (.str (← pad (← vget vin "val") (padding := ← vget vin "pad")
        (padchar := ← vget vin "char")))))
    (flagNull := false)
  runSet "minor.pathify" (← mg "pathify")
    (arg1 (fun vin => do
      if ← vhas vin "path" then
        pure (.str (← pathify (← vget vin "path") (startin := ← vget vin "from")))
      else
        pure (.str (← pathify .noval (startin := ← vget vin "from") (absent := true)))))
    (flagNull := false)
  runSet "minor.items" (← mg "items") (arg1 items)
  -- Canonical omits `alt` only when the KEY is missing (`undefined ===
  -- vin.alt`), so a present `alt: null` still goes through; getelem's rule is
  -- the looser `null == vin.alt`. `minor/getprop#51` is the entry that
  -- separates them - csharp, c, ocaml and scala carried the same confusion.
  runSet "minor.getprop" (← mg "getprop")
    (arg1 (fun vin => do
      if ← vhas vin "alt" then
        getprop (← vget vin "val") (← vget vin "key") (← vget vin "alt")
      else getprop (← vget vin "val") (← vget vin "key")))
    (flagNull := false)
  runSet "minor.setprop" (← mg "setprop")
    (arg1 (fun vin => do
      setprop (← vget vin "parent") (← vget vin "key") (← vget vin "val")))
  runSet "minor.haskey" (← mg "haskey")
    (arg1 (fun vin => do
      pure (.bool (← haskey (← vget vin "src") (← vget vin "key")))))
    (flagNull := false)
  runSet "minor.keysof" (← mg "keysof")
    (arg1 (fun v => do newList ((← keysof v).map (fun s => Value.str s))))
  runSet "minor.join" (← mg "join")
    (arg1 (fun vin => do
      let url := (← vget vin "url") == .bool true
      pure (.str (← join (← vget vin "val") (sep := ← vget vin "sep") (url := url)))))
    (flagNull := false)
  runSet "minor.typify" (← mg "typify")
    (arg1 (fun v => pure (vInt (typify v))))
    (flagNull := false)
  runSet "minor.setpath" (← mg "setpath")
    (arg1 (fun vin => do
      setpath (← vget vin "store") (← vget vin "path") (← vget vin "val")))
    (flagNull := false)
  runSet "minor.filter" (← mg "filter")
    (arg1 (fun vin => do
      let checkV ← vget vin "check"
      let check : (String × Value) → Bool :=
        if checkV == .str "gt3" then
          fun (_, x) => match x with | .num n => n > 3.0 | _ => false
        else if checkV == .str "lt3" then
          fun (_, x) => match x with | .num n => n < 3.0 | _ => false
        else fun _ => false
      filter (← vget vin "val") check))
  runSet "minor.typename" (← mg "typename")
    (arg1 (fun v => do
      let t : Int := match v with
        | .num n => fToInt n
        | _ => 0
      pure (.str (typename t))))
  runSet "minor.flatten" (← mg "flatten")
    (arg1 (fun vin => do
      match (← vget vin "depth") with
      | .num n => flatten (← vget vin "val") (depth := fToInt n)
      | _ => flatten (← vget vin "val")))

  -- walk
  runWalkLog "walk.log" (← getpropRawPub walks "log")
  runSet "walk.basic" (← getpropRawPub walks "basic")
    (arg1 (fun vin => do
      walk vin (after := some (fun _k v _p path => do
        match v with
        | .str s => do
          let mut parts : List String := []
          for x in (← listItemsOf path) do
            parts := (← jsString x) :: parts
          pure (.str (s ++ "~" ++ String.intercalate "." parts.reverse))
        | _ => pure v))))
  runSet "walk.copy" (← getpropRawPub walks "copy") (arg1 walkCopySubject)
  runSet "walk.depth" (← getpropRawPub walks "depth") (arg1 walkDepthSubject)
    (flagNull := false)

  -- merge
  runSingle "merge.basic" (← getpropRawPub merges "basic")
    (fun vin => do merge (← clone vin))
  runSet "merge.cases" (← getpropRawPub merges "cases") (arg1 (fun v => merge v))
  runSet "merge.array" (← getpropRawPub merges "array") (arg1 (fun v => merge v))
  runSet "merge.integrity" (← getpropRawPub merges "integrity") (arg1 (fun v => merge v))
  runSet "merge.depth" (← getpropRawPub merges "depth")
    (arg1 (fun vin => do
      merge (← vget vin "val") (maxdepth := ← vget vin "depth")))

  -- getpath
  runSet "getpath.basic" (← getpropRawPub getpaths "basic")
    (arg1 (fun vin => do getpath (← vget vin "store") (← vget vin "path")))
  runSet "getpath.relative" (← getpropRawPub getpaths "relative")
    (arg1 (fun vin => do
      let dpath ← match (← vget vin "dpath") with
        | .str s => newList ((s.splitOn ".").map (fun x => Value.str x)).toArray
        | _ => pure Value.noval
      let d : InjDef := { dDparent := ← vget vin "dparent", dDpath := dpath }
      getpath (← vget vin "store") (← vget vin "path") (.idef d)))
  runSet "getpath.special" (← getpropRawPub getpaths "special")
    (arg1 (fun vin => do
      let injm ← vget vin "inj"
      let d : InjDef := {
        dBase := ← getprop injm (.str "base"), dMeta := ← getprop injm (.str "meta"),
        dDparent := ← getprop injm (.str "dparent"), dDpath := ← getprop injm (.str "dpath"),
        dKey := ← getprop injm (.str "key") }
      getpath (← vget vin "store") (← vget vin "path")
        (if isNullish injm then .inone else .idef d)))
  runSet "getpath.handler" (← getpropRawPub getpaths "handler")
    (arg1 (fun vin => do
      let foo ← vFunc (fun _ _ _ _ => pure (.str "foo"))
      let store ← omapV [("$TOP", ← vget vin "store"), ("$FOO", foo)]
      let h ← registerFunc (fun _inj v _ref _store => do
        match v with
        | .func fid => callFunc fid (← getDummyInj) .noval "" .noval
        | _ => pure v)
      let d : InjDef := { dHandler := some h }
      getpath store (← vget vin "path") (.idef d)))

  -- inject
  runSingle "inject.basic" (← getpropRawPub injects "basic")
    (fun vin => do
      inject (← clone (← getpropRawPub vin "val")) (← clone (← getpropRawPub vin "store")))
  runSet "inject.string" (← getpropRawPub injects "string")
    (arg1 (fun vin => do
      let mid ← registerModify nullModifier
      let d : InjDef := { dModify := some mid, dExtra := ← vget vin "current" }
      inject (← vget vin "val") (← vget vin "store") (.idef d)))
  runSet "inject.deep" (← getpropRawPub injects "deep")
    (arg1 (fun vin => do inject (← vget vin "val") (← vget vin "store")))

  -- transform
  runSingle "transform.basic" (← getpropRawPub transforms "basic")
    (fun vin => do
      transform (← getpropRawPub vin "data") (← getpropRawPub vin "spec"))
  for gn in ["paths", "cmds", "each", "pack", "ref"] do
    runSet ("transform." ++ gn) (← getpropRawPub transforms gn)
      (arg1 (fun vin => do transform (← vget vin "data") (← vget vin "spec")))
  runSet "transform.modify" (← getpropRawPub transforms "modify")
    (arg1 (fun vin => do
      let mid ← registerModify (fun v key parent _inj => do
        match v with
        | .str s =>
          if !(isNullish key) && !(isNullish parent) then
            let _ ← setprop parent key (.str ("@" ++ s))
        | _ => pure ())
      let d : InjDef := { dModify := some mid, dExtra := ← vget vin "store" }
      transform (← vget vin "data") (← vget vin "spec") (.idef d)))
  runSet "transform.format" (← getpropRawPub transforms "format")
    (arg1 (fun vin => do transform (← vget vin "data") (← vget vin "spec")))
    (flagNull := false)
  runSet "transform.apply" (← getpropRawPub transforms "apply")
    (arg1 (fun vin => do transform (← vget vin "data") (← vget vin "spec")))

  -- validate
  runSet "validate.basic" (← getpropRawPub validates "basic")
    (arg1 (fun vin => do validate (← vget vin "data") (← vget vin "spec")))
    (flagNull := false)
  for gn in ["child", "one", "exact"] do
    runSet ("validate." ++ gn) (← getpropRawPub validates gn)
      (arg1 (fun vin => do validate (← vget vin "data") (← vget vin "spec")))
  runSet "validate.invalid" (← getpropRawPub validates "invalid")
    (arg1 (fun vin => do validate (← vget vin "data") (← vget vin "spec")))
    (flagNull := false)
  runSet "validate.special" (← getpropRawPub validates "special")
    (arg1 (fun vin => do
      let injm ← vget vin "inj"
      let d : InjDef := { dMeta := ← getprop injm (.str "meta") }
      validate (← vget vin "data") (← vget vin "spec")
        (if isNullish injm then .inone else .idef d)))

  -- select
  for gn in ["basic", "operators", "edge", "alts"] do
    runSet ("select." ++ gn) (← getpropRawPub selects gn)
      (arg1 (fun vin => do select (← vget vin "obj") (← vget vin "query")))

  -- `null: false` keeps a JSON null an ACTUAL null rather than the NULLMARK
  -- string, so select sees a present-but-null field.
  runSet "select.nullkey" (← getpropRawPub selects "nullkey")
    (arg1 (fun vin => do select (← vget vin "obj") (← vget vin "query")))
    (flagNull := false)

  -- regex (parity floor: Go stdlib regexp — see design/REGEX_API.md)
  let regexs ← g "regex"
  runSet "regex.test" (← getpropRawPub regexs "test")
    (arg1 (fun vin => do
      reTest (← vget vin "pattern") (← vget vin "input")))
  runSet "regex.find" (← getpropRawPub regexs "find")
    (arg1 (fun vin => do
      reFind (← vget vin "pattern") (← vget vin "input")))
  runSet "regex.find_all" (← getpropRawPub regexs "find_all")
    (arg1 (fun vin => do
      reFindAll (← vget vin "pattern") (← vget vin "input")))
  runSet "regex.replace" (← getpropRawPub regexs "replace")
    (arg1 (fun vin => do
      reReplace (← vget vin "pattern") (← vget vin "input") (← vget vin "replacement")))
  runSet "regex.escape" (← getpropRawPub regexs "escape")
    (arg1 (fun vin => do
      reEscape (← vget vin "val")))

  -- sentinels
  runSet "sentinels.getprop_unify" (← getpropRawPub sentinels "getprop_unify")
    (arg1 (fun vin => do
      getprop (← vget vin "val") (← vget vin "key") (← vget vin "alt")))
    (flagNull := false)
  runSet "sentinels.getelem_absent" (← getpropRawPub sentinels "getelem_absent")
    (arg1 (fun vin => do
      getelem (← vget vin "val") (← vget vin "key") (← vget vin "alt")))
    (flagNull := false)
  runSet "sentinels.haskey_unify" (← getpropRawPub sentinels "haskey_unify")
    (arg1 (fun vin => do
      pure (.bool (← haskey (← vget vin "val") (← vget vin "key")))))
    (flagNull := false)
  runSet "sentinels.isempty_unify" (← getpropRawPub sentinels "isempty_unify")
    (arg1 (fun v => do pure (.bool (← isempty v))))
    (flagNull := false)
  runSet "sentinels.isnode_unify" (← getpropRawPub sentinels "isnode_unify")
    (arg1 (fun v => pure (.bool (isnode v))))
    (flagNull := false)
  runSet "sentinels.stringify_null" (← getpropRawPub sentinels "stringify_null")
    (arg1 (fun vin => do pure (.str (← stringify vin))))
    (flagNull := false)

-- ---------------- main ----------------

/-- `DEF.client`, client-scoped options, and `contextify`. This port had no
such test. It is the only thing that exercises subject resolution through a
PROVIDER rather than through a callback this file hands over - so nothing here
had ever checked that a corpus `client` key resolves, or that a `DEF.client`
entry's options reach the subject.

The subject talks to omni DIRECTLY, in omni's own value type: the runner
resolves it by name off the provider, so there is no `in` to convert and no
result for the bridge to convert back. -/
def check (options : Lean.Json) : Omni.Subject := fun args =>
  let foo := Omni.jget (some options) "foo"
  let foos := if Omni.isabsent foo then "" else Omni.stringify foo
  let ctx := args.getD 0 none
  let bar := Omni.jget (Omni.jget ctx "meta") "bar"
  let bars := if Omni.isnone bar then "0" else Omni.stringify bar
  .ok (some (Omni.jmap [("zed", Omni.jstr ("ZED" ++ foos ++ "_" ++ bars))]))

partial def clientProvider (options : Lean.Json) : Omni.Provider :=
  Omni.provider
    (subject := some (fun name => if name == "check" then some (check options) else none))
    -- A DEF.client entry becomes another provider, carrying its options.
    (client := some clientProvider)
    -- This port adds nothing to a context; the hook must exist so omni
    -- installs `client` on it.
    (contextify := some (fun value => value))

def runClient (alltests : Lean.Json) : IO Unit := do
  match Omni.makeRunnerSpec alltests (clientProvider (Omni.jmap [])) "check" with
  | .error message => record "check.basic" false message
  | .ok pack =>
    -- No subject: the runner resolves it by name off the provider, which is
    -- the whole point of the group.
    match pack.runsetflags (pack.set "basic") { name := some "check.basic" } none with
    | .ok () => record "check.basic" true ""
    | .error message => record "check.basic" false message

def main (argv : List String) : IO UInt32 := do
  let testfile := argv.headD "../build/test/test.json"
  let alltests ← Omni.loadspec testfile
  let ctx ← mkCtx
  let pack ← match Omni.makeRunnerSpec alltests Omni.emptyProvider "struct" with
    | .ok pack => pure pack
    | .error message => throw (IO.userError message)
  runpack.set (some pack)
  let go : SIO Unit := do
    runAll (← tostruct (some pack.spec))
  go.run ctx
  runClient alltests
  for f in (← failures.get).reverse do
    IO.println f
  IO.println ""
  IO.println (toString ((← npass.get) + (← nfail.get)) ++ " groups, "
    ++ toString (← nfail.get) ++ " failed")
  if (← nfail.get) > 0 then return 1 else return 0
