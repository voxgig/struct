/- Test runner for the shared JSON corpus (build/test/test.json).
   Self-contained: an in-tree JSON reader builds the library's `Value` type
   directly, so the Lean port is exercised exactly as in production. -/

import VoxgigStruct

open VoxgigStruct

def nullmark : String := "__NULL__"
def undefmark : String := "__UNDEF__"
def existsmark : String := "__EXISTS__"

-- ---------------- JSON reader -> Value ----------------

structure JState where
  src : Array Char
  pos : Nat

partial def jPeek (s : JState) : Option Char := s.src[s.pos]?

partial def jSkipWs (s : JState) : JState := Id.run do
  let mut p := s.pos
  while p < s.src.size &&
      (s.src[p]! == ' ' || s.src[p]! == '\t' || s.src[p]! == '\n' || s.src[p]! == '\r') do
    p := p + 1
  return { s with pos := p }

partial def jStr (s0 : JState) : SIO (String × JState) := do
  -- assumes current char is '"'
  let src := s0.src
  let mut p := s0.pos + 1
  let mut b := ""
  repeat do
    if p >= src.size then break
    let c := src[p]!
    p := p + 1
    if c == '"' then break
    if c == '\\' then
      let e := src[p]!
      p := p + 1
      match e with
      | '"' => b := b.push '"'
      | '\\' => b := b.push '\\'
      | '/' => b := b.push '/'
      | 'n' => b := b.push '\n'
      | 't' => b := b.push '\t'
      | 'r' => b := b.push '\r'
      | 'b' => b := b.push '\x08'
      | 'f' => b := b.push '\x0c'
      | 'u' => do
        let mut code : Nat := 0
        for _ in [0:4] do
          let h := src[p]!
          p := p + 1
          let d :=
            if h >= '0' && h <= '9' then h.toNat - '0'.toNat
            else if h >= 'a' && h <= 'f' then 10 + h.toNat - 'a'.toNat
            else if h >= 'A' && h <= 'F' then 10 + h.toNat - 'A'.toNat
            else 0
          code := code * 16 + d
        b := b.push (Char.ofNat code)
      | c => b := b.push c
    else
      b := b.push c
  return (b, { s0 with pos := p })

mutual

partial def jVal (s0 : JState) : SIO (Value × JState) := do
  let s := jSkipWs s0
  match jPeek s with
  | some '{' => jObj s
  | some '[' => jArr s
  | some '"' => do
    let (str, s') ← jStr s
    pure (.str str, s')
  | some 't' => pure (.bool true, { s with pos := s.pos + 4 })
  | some 'f' => pure (.bool false, { s with pos := s.pos + 5 })
  | some 'n' => pure (.null, { s with pos := s.pos + 4 })
  | _ => jNum s

partial def jObj (s0 : JState) : SIO (Value × JState) := do
  let s := jSkipWs { s0 with pos := s0.pos + 1 }
  if jPeek s == some '}' then
    pure (← emptyMap, { s with pos := s.pos + 1 })
  else do
    let m ← emptyMap
    let sRef ← IO.mkRef s
    repeat do
      let s1 := jSkipWs (← sRef.get)
      let (k, s2) ← jStr s1
      let s3 := jSkipWs s2
      let s4 := { s3 with pos := s3.pos + 1 }  -- ':'
      let (v, s5) ← jVal s4
      let _ ← setprop m (.str k) v
      let s6 := jSkipWs s5
      let c := (jPeek s6).getD '}'
      sRef.set { s6 with pos := s6.pos + 1 }
      if c != ',' then break
    pure (m, ← sRef.get)

partial def jArr (s0 : JState) : SIO (Value × JState) := do
  let s := jSkipWs { s0 with pos := s0.pos + 1 }
  if jPeek s == some ']' then
    pure (← emptyList, { s with pos := s.pos + 1 })
  else do
    let sRef ← IO.mkRef s
    let accRef ← IO.mkRef (#[] : Array Value)
    repeat do
      let (v, s1) ← jVal (← sRef.get)
      accRef.modify (·.push v)
      let s2 := jSkipWs s1
      let c := (jPeek s2).getD ']'
      sRef.set { s2 with pos := s2.pos + 1 }
      if c != ',' then break
    pure (← newList (← accRef.get), ← sRef.get)

partial def jNum (s0 : JState) : SIO (Value × JState) := do
  let src := s0.src
  let mut p := s0.pos
  let start := p
  while p < src.size &&
      (let c := src[p]!
       (c >= '0' && c <= '9') || c == '-' || c == '+' || c == '.' || c == 'e' || c == 'E') do
    p := p + 1
  let tok := String.ofList (src.extract start p).toList
  pure (.num ((parseFloatJS tok).getD 0.0), { s0 with pos := p })

end

def jsonRead (s : String) : SIO Value := do
  pure (← jVal { src := s.toList.toArray, pos := 0 }).1

-- ---------------- fixJSON / equality ----------------

partial def fixJson (v : Value) (flagNull : Bool) : SIO Value := do
  match v with
  | .noval | .null => if flagNull then pure (.str nullmark) else pure v
  | .map id => do
    let o ← emptyMap
    for (k, x) in (← mapEntries id) do
      let _ ← setprop o (.str k) (← fixJson x flagNull)
    pure o
  | .list id => do
    let mut out : Array Value := #[]
    for x in (← listItems id) do
      out := out.push (← fixJson x flagNull)
    newList out
  | _ => pure v

/-- Order-independent deep equality for maps; sequence equality for lists. -/
partial def eqv (a b : Value) : SIO Bool := do
  match a, b with
  | .noval, .noval | .noval, .null | .null, .noval | .null, .null => pure true
  | .bool x, .bool y => pure (x == y)
  | .num x, .num y => pure (x == y)
  | .str x, .str y => pure (x == y)
  | .list x, .list y => do
    let xs ← listItems x
    let ys ← listItems y
    if xs.size != ys.size then pure false
    else do
      for i in [0:xs.size] do
        if !(← eqv xs[i]! ys[i]!) then return false
      pure true
  | .map x, .map y => do
    let xes ← mapEntries x
    let yes ← mapEntries y
    if xes.size != yes.size then pure false
    else do
      for (k, v) in xes do
        match omapGet yes k with
        | some w =>
          if !(← eqv v w) then return false
        | none => return false
      pure true
  | _, _ => pure (a == b)

-- ---------------- match support ----------------

def strContainsSub (hay needle : String) : Bool := Id.run do
  let h := hay.toList.toArray
  let nd := needle.toList.toArray
  if nd.size == 0 then return true
  if nd.size > h.size then return false
  for i in [0:h.size - nd.size + 1] do
    let mut ok := true
    for j in [0:nd.size] do
      if h[i + j]! != nd[j]! then ok := false
    if ok then return true
  return false

partial def matchval (check0 base : Value) : SIO Bool := do
  let check := if check0 == .str undefmark || check0 == .str nullmark then Value.noval
               else check0
  if ← eqv check base then pure true
  else match check with
    | .str cs => do
      let basestr ← stringify base
      let csArr := cs.toList.toArray
      if csArr.size >= 2 && csArr[0]! == '/' && csArr[csArr.size - 1]! == '/' then
        pure (Vregex.testStr (String.ofList (csArr.extract 1 (csArr.size - 1)).toList) basestr)
      else
        pure (strContainsSub basestr.toLower (← stringify check).toLower)
    | .func _ => pure true
    | _ => pure false

partial def doMatch (check base0 : Value) : SIO Unit := do
  let base ← clone base0
  let _ ← walk check (before := some (fun _k v _p path => do
    if !(isnode v) then do
      let baseval ← getpath base path
      if ← eqv baseval v then pure ()
      else if v == .str undefmark && isNullish baseval then pure ()
      else if v == .str existsmark && !(isNullish baseval) then pure ()
      else if !(← matchval v baseval) then do
        let mut parts : List String := []
        for x in (← listItemsOf path) do
          parts := (← jsString x) :: parts
        throw (IO.userError ("MATCH: " ++ String.intercalate "." parts.reverse
          ++ ": [" ++ (← stringify v) ++ "] <=> [" ++ (← stringify baseval) ++ "]"))
    pure v))
  pure ()

-- ---------------- result tracking ----------------

initialize npass : IO.Ref Nat ← IO.mkRef 0
initialize nfail : IO.Ref Nat ← IO.mkRef 0
initialize failures : IO.Ref (List String) ← IO.mkRef []

def record (group name : String) (ok : Bool) (msg : String) : IO Unit := do
  if ok then npass.modify (· + 1)
  else do
    nfail.modify (· + 1)
    failures.modify (("FAIL " ++ group ++ " " ++ name ++ " - " ++ msg) :: ·)

-- ---------------- per-entry runner ----------------

def omapV (kvs : List (String × Value)) : SIO Value := do
  let m ← emptyMap
  for (k, v) in kvs do
    let _ ← setprop m (.str k) v
  pure m

def entryGet (e : Value) (k : String) : SIO Value := do
  match e with
  | .map id => pure ((omapGet (← mapEntries id) k).getD .noval)
  | _ => pure .noval

def entryHas (e : Value) (k : String) : SIO Bool := do
  match e with
  | .map id => pure (omapHas (← mapEntries id) k)
  | _ => pure false

def resolveArgs (entry : Value) : SIO (List Value) := do
  if ← entryHas entry "ctx" then pure [← entryGet entry "ctx"]
  else if ← entryHas entry "args" then pure (← listItemsOf (← entryGet entry "args")).toList
  else if ← entryHas entry "in" then pure [← clone (← entryGet entry "in")]
  else pure [.noval]

def checkResult (entry : Value) (args : List Value) (res : Value) : SIO Unit := do
  let mut matched := false
  if ← entryHas entry "match" then do
    doMatch (← entryGet entry "match")
      (← omapV [("in", ← entryGet entry "in"), ("args", ← newList args.toArray),
                ("out", ← entryGet entry "res"), ("ctx", ← entryGet entry "ctx")])
    matched := true
  let out ← entryGet entry "out"
  if ← eqv out res then pure ()
  else if matched && (out == .str nullmark || isNullish out) then pure ()
  else
    throw (IO.userError ("Expected: " ++ (← stringify out) ++ ", got: " ++ (← stringify res)))

def handleError (entry : Value) (err : IO.Error) : SIO Unit := do
  let msg := err.toString
  if ← entryHas entry "err" then do
    let entryErr ← entryGet entry "err"
    if entryErr == .bool true || (← matchval entryErr (.str msg)) then do
      if ← entryHas entry "match" then
        doMatch (← entryGet entry "match")
          (← omapV [("in", ← entryGet entry "in"), ("out", ← entryGet entry "res"),
                    ("ctx", ← entryGet entry "ctx"), ("err", .str msg)])
    else
      throw (IO.userError ("ERROR MATCH: [" ++ (← stringify entryErr) ++ "] <=> [" ++ msg ++ "]"))
  else throw err

def runSet (group : String) (node : Value) (subject : List Value → SIO Value)
    (flagNull : Bool := true) : SIO Unit := do
  let fixed ← fixJson node flagNull
  let testset ← listItemsOf (← getprop fixed (.str "set"))
  for entry in testset do
    let name ← jsString (← entryGet entry "name")
    try
      if !(← entryHas entry "out") && flagNull then
        let _ ← setprop entry (.str "out") (.str nullmark)
      let args ← resolveArgs entry
      let res ← fixJson (← subject args) flagNull
      let _ ← setprop entry (.str "res") res
      checkResult entry args res
      record group name true ""
    catch e =>
      try
        handleError entry e
        record group name true ""
      catch e2 =>
        record group name false e2.toString

def getpropRawPub (e : Value) (k : String) : SIO Value := entryGet e k

def runSingle (group : String) (node : Value) (actualFn : Value → SIO Value) : SIO Unit := do
  try
    let expected ← getpropRawPub node "out"
    let actual ← actualFn (← getpropRawPub node "in")
    if ← eqv expected actual then record group "single" true ""
    else
      record group "single" false
        ("Expected: " ++ (← stringify expected) ++ ", got: " ++ (← stringify actual))
  catch e => record group "single" false e.toString

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
    if ← eqv expected log then record group "log" true ""
    else
      record group "log" false
        ("Expected: " ++ (← stringify expected) ++ ", got: " ++ (← stringify log))
  catch e => record group "log" false e.toString

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
  runSet "minor.getprop" (← mg "getprop")
    (arg1 (fun vin => do
      let alt ← vget vin "alt"
      if isNullish alt then getprop (← vget vin "val") (← vget vin "key")
      else getprop (← vget vin "val") (← vget vin "key") alt))
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

def main (argv : List String) : IO UInt32 := do
  let testfile := argv.headD "../build/test/test.json"
  let raw ← IO.FS.readFile testfile
  let ctx ← mkCtx
  let go : SIO Unit := do
    let alltests ← jsonRead raw
    let spec ← getpropRawPub alltests "struct"
    runAll spec
  go.run ctx
  for f in (← failures.get).reverse do
    IO.println f
  IO.println ""
  IO.println ("PASS " ++ toString (← npass.get) ++ "  FAIL " ++ toString (← nfail.get))
  if (← nfail.get) > 0 then return 1 else return 0
