-- The shared corpus, run on the shared runner.
--
-- The in-situ runner - a JSON reader, `fixJson`, `eqv`, `doMatch`, `matchval`,
-- `resolveArgs`, `checkResult` and `handleError`, all of it this port's own
-- copy of omni's algorithm - is gone. Every group is driven through
-- voxgig/omni, so this file only says WHICH subject answers each group and
-- with which flags.
--
-- omni is consumed as a local checkout: the Makefile finds it via $OMNI_HOME
-- or beside this repository and puts its `src` on the TEST search path only.
-- `make build` compiles src/ alone and nothing shipped names omni
-- (register 4.13).
--
-- Flags mirror canonical: typescript/test/utility/StructUtility.test.ts.

module Main where

import Control.Exception (SomeException, try)
import Control.Monad (forM_, when)
import Data.IORef
import Data.List (intercalate)
import System.Environment (getArgs)
import System.Exit (exitFailure)

import VoxgigStruct
import qualified Omni as O

nullmark :: String
nullmark = "__NULL__"

-- ---------------- the bridge ----------------

-- omni's model -> this port's. Both draw the same absent/null/value
-- distinction (`VNoval` is canonical `undefined`), so nothing is guessed.
-- Nodes are built through `mkList` / `mkMap`, so what a subject receives is a
-- real IORef-backed node it may mutate.
tostruct :: O.Json -> IO Value
tostruct value = case value of
  O.Absent -> return VNoval
  O.Null -> return VNull
  O.Bool b -> return (VBool b)
  O.Num n -> return (VNum n)
  O.Str s -> return (VStr s)
  O.JList items -> mapM tostruct items >>= mkList
  O.JMap entries -> mapM (\(key, item) -> (,) key <$> tostruct item) entries >>= mkMap

-- This port's model -> omni's. A function or a sentinel has no JSON form and
-- omni only ever stringifies one, so it becomes its own rendering rather than
-- silently collapsing to null.
toomni :: Value -> IO O.Json
toomni value = case value of
  VNoval -> return O.Absent
  VNull -> return O.Null
  VBool b -> return (O.Bool b)
  VNum n -> return (O.Num n)
  VStr s -> return (O.Str s)
  VList r -> do items <- readIORef r; O.JList <$> mapM toomni items
  VMap m -> do entries <- readIORef m; O.JMap <$> mapM (\(key, item) -> (,) key <$> toomni item) entries
  VFunc _ -> return (O.Str "[Function]")
  VSentinel tag -> return (O.Str ("`$" ++ tag ++ "`"))

-- Order-independent deep equality, through omni's own rule so the hand-written
-- comparisons below match the way every group is checked.
eqv :: Value -> Value -> IO Bool
eqv a b = do
  ja <- toomni a
  jb <- toomni b
  return (O.deepequal ja jb)

-- ---------------- result tracking ----------------

data Counters = Counters { npass :: IORef Int, nfail :: IORef Int, failures :: IORef [String] }

record :: Counters -> String -> Bool -> String -> IO ()
record c group ok msg =
  if ok then modifyIORef' (npass c) (+ 1)
  else do modifyIORef' (nfail c) (+ 1); modifyIORef' (failures c) (++ ["FAIL " ++ group ++ " - " ++ msg])

-- ---------------- running a group ----------------

-- Each group is one assertion: omni stops at its first failing entry and
-- reports the index, the entry and both values.
--
-- The subject is handed omni's arguments converted into this port's nodes, and
-- the wrapper hands the converted arguments BACK - `match.args` asserts an
-- in-place rewrite in eight of `minor/setpath`'s nine entries and all six of
-- `merge/integrity`. This port's nodes are mutable IORef cells but omni's
-- `Json` is not, so returning them alongside the result (omni's `SubjectArgs`)
-- is the only channel there is. rust, cpp, ocaml and elixir needed the same
-- entry point for the same reason.
runSet :: Counters -> O.RunPack -> String -> Value -> ([Value] -> IO Value) -> Bool -> IO ()
runSet c pack group node subject flagNull = do
  spec <- toomni node
  let call cells = do
        args <- mapM tostruct cells
        res <- subject args
        (,) <$> mapM toomni args <*> toomni res
      flags = O.Flags { O.flagNull = flagNull, O.flagName = Just group }
  outcome <- try (O.runsetFlagsArgs pack spec flags call) :: IO (Either SomeException ())
  case outcome of
    Right () -> record c group True ""
    Left err -> record c group False (O.errmessage err)

-- `merge.basic`, `inject.basic` and `transform.basic` are single entries, not
-- sets, so the runner cannot drive them. Compared here, through omni's own
-- deepequal so the rule is the one every group uses.
runSingle :: Counters -> String -> Value -> (Value -> IO Value) -> IO ()
runSingle c group node actualFn = do
  outcome <- try go :: IO (Either SomeException ())
  case outcome of
    Right () -> return ()
    Left err -> record c group False (O.errmessage err)
  where
    go = do
      expected <- getpropRaw node "out"
      inv <- getpropRaw node "in"
      actual <- actualFn inv
      same <- eqv expected actual
      if same then record c group True ""
      else do
        se <- stringify expected
        sa <- stringify actual
        record c group False ("Expected: " ++ se ++ ", got: " ++ sa)

-- ---------------- arg helpers ----------------

arg1 :: (Value -> IO Value) -> [Value] -> IO Value
arg1 f = \args -> f (case args of (x:_) -> x; [] -> VNoval)

vget :: Value -> String -> IO Value
vget vin k = case vin of { VMap m -> do { es <- readIORef m; return (maybe VNoval id (lookup k es)) }; _ -> return VNoval }

vhas :: Value -> String -> IO Bool
vhas vin k = case vin of { VMap m -> do { es <- readIORef m; return (any ((== k) . fst) es) }; _ -> return False }

-- ---------------- main ----------------

main :: IO ()
main = do
  argv <- getArgs
  let testfile = case argv of (f:_) -> f; [] -> "../build/test/test.json"
  pack <- O.makeRunner testfile O.emptyProvider "struct"
  spec <- tostruct (O.packSpec pack)
  c <- Counters <$> newIORef 0 <*> newIORef 0 <*> newIORef []
  runAll c pack spec
  runClient c testfile
  fs <- readIORef (failures c)
  forM_ fs putStrLn
  p <- readIORef (npass c)
  f <- readIORef (nfail c)
  putStrLn ("\n" ++ show (p + f) ++ " groups, " ++ show f ++ " failed")
  when (f > 0) exitFailure

-- ---------------- the client path ----------------

-- `DEF.client`, client-scoped options, and `contextify`. This port had no such
-- test. It is the only thing that exercises subject resolution through a
-- PROVIDER rather than through a callback this file hands over - so nothing
-- here had ever checked that a corpus `client` key resolves, or that a
-- `DEF.client` entry's options reach the subject.
--
-- The subject talks to omni DIRECTLY, in omni's own value type: the runner
-- resolves it by name off the provider, so there is no `in` to convert and no
-- result for the bridge to convert back.
check :: O.Json -> O.Subject
check options args = do
  let foo = O.jget options "foo"
      foos = if O.isabsent foo then "" else O.stringify foo
      ctx = case args of (first:_) -> first; [] -> O.Absent
      bar = O.jget (O.jget ctx "meta") "bar"
      bars = if O.isnone bar then "0" else O.stringify bar
  return (O.JMap [("zed", O.Str ("ZED" ++ foos ++ "_" ++ bars))])

clientProvider :: O.Json -> O.Provider
clientProvider options =
  O.Provider
    { O.providerSubject = Just (\name -> if name == "check" then Just (check options) else Nothing),
      -- A DEF.client entry becomes another provider, carrying its options.
      O.providerClient = Just clientProvider,
      -- This port adds nothing to a context; the hook must exist so omni
      -- installs `client` on it.
      O.providerContextify = Just id,
      O.providerInject = Nothing
    }

runClient :: Counters -> String -> IO ()
runClient c testfile = do
  pack <- O.makeRunner testfile (clientProvider (O.JMap [])) "check"
  let flags = O.Flags { O.flagNull = True, O.flagName = Just "check.basic" }
  -- No subject: the runner resolves it by name off the provider, which is the
  -- whole point of the group.
  outcome <- try (O.runsetFlags pack (O.packSet pack "basic") flags Nothing) :: IO (Either SomeException ())
  case outcome of
    Right () -> record c "check.basic" True ""
    Left err -> record c "check.basic" False (O.errmessage err)

-- ---------------- test groups ----------------

nullModifier :: Value -> Value -> Value -> Inj -> IO ()
nullModifier v key parent _inj =
  if vStrEq v nullmark then setprop parent key VNull >> return ()
  else case v of
    VStr s -> do _ <- setprop parent key (VStr (replaceAll s nullmark "null")); return ()
    _ -> return ()

runAll :: Counters -> O.RunPack -> Value -> IO ()
runAll c pack spec = do
  let g k = getpropRaw spec k
  minor <- g "minor"; walks <- g "walk"; merges <- g "merge"
  getpaths <- g "getpath"; injects <- g "inject"; transforms <- g "transform"
  validates <- g "validate"; selects <- g "select"; sentinels <- g "sentinels"
  regexs <- g "regex"
  let mg k = getpropRaw minor k
      rs group nd subj fl = do n <- nd; runSet c pack group n subj fl
      rsT group nd subj = rs group nd subj True
      rsF group nd subj = rs group nd subj False

  rsT "minor.isnode" (mg "isnode") (arg1 (\v -> return (VBool (isnode v))))
  rsT "minor.ismap" (mg "ismap") (arg1 (\v -> return (VBool (ismap v))))
  rsT "minor.islist" (mg "islist") (arg1 (\v -> return (VBool (islist v))))
  rsF "minor.iskey" (mg "iskey") (arg1 (\v -> return (VBool (iskey v))))
  rsF "minor.strkey" (mg "strkey") (arg1 (\v -> return (VStr (strkey v))))
  rsF "minor.isempty" (mg "isempty") (arg1 (\v -> VBool <$> isempty v))
  rsT "minor.isfunc" (mg "isfunc") (arg1 (\v -> return (VBool (isfunc v))))
  rsF "minor.clone" (mg "clone") (arg1 clone)
  rsT "minor.escre" (mg "escre") (arg1 escre)
  rsT "minor.escurl" (mg "escurl") (arg1 escurl)
  rsF "minor.stringify" (mg "stringify") (arg1 (\vin -> do
    h <- vhas vin "val"
    if h then do val <- vget vin "val"; mx <- vget vin "max"; VStr <$> stringifyMax val mx
    else VStr <$> stringify VNoval))
  rsF "minor.jsonify" (mg "jsonify") (arg1 (\vin -> do val <- vget vin "val"; fl <- vget vin "flags"; VStr <$> jsonify val fl))
  rsF "minor.getelem" (mg "getelem") (arg1 (\vin -> do
    alt <- vget vin "alt"; val <- vget vin "val"; key <- vget vin "key"
    if isNullish alt then getelem val key else getelemAlt alt val key))
  rsT "minor.delprop" (mg "delprop") (arg1 (\vin -> do p <- vget vin "parent"; k <- vget vin "key"; delprop p k))
  rsF "minor.size" (mg "size") (arg1 (\v -> vint <$> size v))
  rsF "minor.slice" (mg "slice") (arg1 (\vin -> do val <- vget vin "val"; st <- vget vin "start"; en <- vget vin "end"; slice val st en))
  rsF "minor.pad" (mg "pad") (arg1 (\vin -> do val <- vget vin "val"; pd <- vget vin "pad"; ch <- vget vin "char"; VStr <$> pad val pd ch))
  rsF "minor.pathify" (mg "pathify") (arg1 (\vin -> do
    h <- vhas vin "path"; frm <- vget vin "from"
    if h then do pth <- vget vin "path"; VStr <$> pathifyFull pth frm VNoval False
    else VStr <$> pathifyFull VNoval frm VNoval True))
  rsT "minor.items" (mg "items") (arg1 items)
  -- Canonical omits `alt` only when the KEY is missing (`undefined === vin.alt`),
  -- so a present `alt: null` still goes through. getelem's rule is the looser
  -- `null == vin.alt`; `minor/getprop#51` is the entry that separates them.
  rsF "minor.getprop" (mg "getprop") (arg1 (\vin -> do
    h <- vhas vin "alt"; val <- vget vin "val"; key <- vget vin "key"
    if h then do alt <- vget vin "alt"; getpropAlt alt val key else getprop val key))
  rsT "minor.setprop" (mg "setprop") (arg1 (\vin -> do p <- vget vin "parent"; k <- vget vin "key"; val <- vget vin "val"; setprop p k val))
  rsF "minor.haskey" (mg "haskey") (arg1 (\vin -> do s <- vget vin "src"; k <- vget vin "key"; VBool <$> haskey s k))
  rsT "minor.keysof" (mg "keysof") (arg1 (\v -> do ks <- keysof v; mkList (map VStr ks)))
  rsF "minor.join" (mg "join") (arg1 (\vin -> do val <- vget vin "val"; sep <- vget vin "sep"; url <- vget vin "url"; VStr <$> join val sep (vIsTrue url)))
  rsF "minor.typify" (mg "typify") (arg1 (\v -> return (vint (typify v))))
  rsF "minor.setpath" (mg "setpath") (arg1 (\vin -> do st <- vget vin "store"; pth <- vget vin "path"; val <- vget vin "val"; setpath st pth val))
  rsT "minor.filter" (mg "filter") (arg1 (\vin -> do
    val <- vget vin "val"; ch <- vget vin "check"
    let check2 = case ch of
          VStr "gt3" -> \(_, x) -> case x of VNum n -> n > 3; _ -> False
          VStr "lt3" -> \(_, x) -> case x of VNum n -> n < 3; _ -> False
          _ -> \_ -> False
    VoxgigStruct.filter val check2))
  rsT "minor.typename" (mg "typename") (arg1 (\v -> return (VStr (typename (case v of VNum n -> truncate n; _ -> 0)))))
  rsT "minor.flatten" (mg "flatten") (arg1 (\vin -> do
    val <- vget vin "val"; d <- vget vin "depth"
    flatten (case d of VNum n -> truncate n; _ -> 1) val))

  runWalkLog c "walk.log" =<< getpropRaw walks "log"
  do nd <- getpropRaw walks "basic"
     rs "walk.basic" (return nd) (arg1 (\vin -> walk Nothing (Just (\_ v _ path ->
       case v of { VStr s -> do { pelems <- listItems path; pstrs <- mapM jsString pelems; return (VStr (s ++ "~" ++ intercalate "." pstrs)) }; _ -> return v })) VNoval vin)) True
  do nd <- getpropRaw walks "copy"; rs "walk.copy" (return nd) (arg1 (walkCopySubject)) True
  do nd <- getpropRaw walks "depth"; rs "walk.depth" (return nd) (arg1 (walkDepthSubject)) False

  do nd <- getpropRaw merges "basic"; runSingle c "merge.basic" nd (\in_ -> clone in_ >>= merge)
  rsT "merge.cases" (getpropRaw merges "cases") (arg1 merge)
  rsT "merge.array" (getpropRaw merges "array") (arg1 merge)
  rsT "merge.integrity" (getpropRaw merges "integrity") (arg1 merge)
  rsT "merge.depth" (getpropRaw merges "depth") (arg1 (\vin -> do val <- vget vin "val"; d <- vget vin "depth"; mergeD val d))

  rsT "getpath.basic" (getpropRaw getpaths "basic") (arg1 (\vin -> do st <- vget vin "store"; pth <- vget vin "path"; getpath INone st pth))
  rsT "getpath.relative" (getpropRaw getpaths "relative") (arg1 (\vin -> do
    st <- vget vin "store"; pth <- vget vin "path"; dpv <- vget vin "dpath"; dpar <- vget vin "dparent"
    dpath <- case dpv of VStr s -> mkList (map VStr (splitOn '.' s)); _ -> return VNoval
    let d = (defaultInjDef VNoval) { dDparent = dpar, dDpath = dpath }
    getpath (IDef d) st pth))
  rsT "getpath.special" (getpropRaw getpaths "special") (arg1 (\vin -> do
    st <- vget vin "store"; pth <- vget vin "path"; injm <- vget vin "inj"
    bs <- getprop injm (VStr "base"); mt <- getprop injm (VStr "meta"); dpar <- getprop injm (VStr "dparent"); dpt <- getprop injm (VStr "dpath"); ky <- getprop injm (VStr "key")
    let d = (defaultInjDef VNoval) { dBase = bs, dMeta = mt, dDparent = dpar, dDpath = dpt, dKey = ky }
    getpath (if isNullish injm then INone else IDef d) st pth))
  rsT "getpath.handler" (getpropRaw getpaths "handler") (arg1 (\vin -> do
    stv <- vget vin "store"; pth <- vget vin "path"
    store <- mkMap [("$TOP", stv), ("$FOO", VFunc (\_ _ _ _ -> return (VStr "foo")))]
    let d = (defaultInjDef VNoval) { dHandler = Just (\_inj v _ref _store -> case v of VFunc f -> f dummyInj VNoval "" VNoval; _ -> return v) }
    getpath (IDef d) store pth))

  do nd <- getpropRaw injects "basic"; runSingle c "inject.basic" nd (\in_ -> do val <- getpropRaw in_ "val" >>= clone; st <- getpropRaw in_ "store" >>= clone; inject INone val st)
  rsT "inject.string" (getpropRaw injects "string") (arg1 (\vin -> do val <- vget vin "val"; st <- vget vin "store"; cur <- vget vin "current"; let d = (defaultInjDef VNoval) { dModify = Just nullModifier, dExtra = cur } in inject (IDef d) val st))
  rsT "inject.deep" (getpropRaw injects "deep") (arg1 (\vin -> do val <- vget vin "val"; st <- vget vin "store"; inject INone val st))

  do nd <- getpropRaw transforms "basic"; runSingle c "transform.basic" nd (\in_ -> do dat <- getpropRaw in_ "data"; sp <- getpropRaw in_ "spec"; transform INone dat sp)
  forM_ ["paths", "cmds", "each", "pack", "ref"] $ \gn ->
    rsT ("transform." ++ gn) (getpropRaw transforms gn) (arg1 (\vin -> do dat <- vget vin "data"; sp <- vget vin "spec"; transform INone dat sp))
  rsT "transform.modify" (getpropRaw transforms "modify") (arg1 (\vin -> do
    dat <- vget vin "data"; sp <- vget vin "spec"; st <- vget vin "store"
    let modf = \v key parent _inj -> case v of VStr s | not (isNullish key) && not (isNullish parent) -> setprop parent key (VStr ("@" ++ s)) >> return (); _ -> return ()
        d = (defaultInjDef VNoval) { dModify = Just modf, dExtra = st }
    transform (IDef d) dat sp))
  rsF "transform.format" (getpropRaw transforms "format") (arg1 (\vin -> do dat <- vget vin "data"; sp <- vget vin "spec"; transform INone dat sp))
  rsT "transform.apply" (getpropRaw transforms "apply") (arg1 (\vin -> do dat <- vget vin "data"; sp <- vget vin "spec"; transform INone dat sp))

  rsF "validate.basic" (getpropRaw validates "basic") (arg1 (\vin -> do dat <- vget vin "data"; sp <- vget vin "spec"; validate INone dat sp))
  forM_ ["child", "one", "exact"] $ \gn ->
    rsT ("validate." ++ gn) (getpropRaw validates gn) (arg1 (\vin -> do dat <- vget vin "data"; sp <- vget vin "spec"; validate INone dat sp))
  rsF "validate.invalid" (getpropRaw validates "invalid") (arg1 (\vin -> do dat <- vget vin "data"; sp <- vget vin "spec"; validate INone dat sp))
  rsT "validate.special" (getpropRaw validates "special") (arg1 (\vin -> do
    dat <- vget vin "data"; sp <- vget vin "spec"; injm <- vget vin "inj"
    mt <- getprop injm (VStr "meta")
    let d = (defaultInjDef VNoval) { dMeta = mt }
    validate (if isNullish injm then INone else IDef d) dat sp))

  forM_ ["basic", "operators", "edge", "alts"] $ \gn ->
    rsT ("select." ++ gn) (getpropRaw selects gn) (arg1 (\vin -> do obj <- vget vin "obj"; qry <- vget vin "query"; select obj qry))
  -- `null: false` keeps a JSON null an ACTUAL null rather than the NULLMARK
  -- string, so select sees a present-but-null field.
  rsF "select.nullkey" (getpropRaw selects "nullkey")
    (arg1 (\vin -> do obj <- vget vin "obj"; qry <- vget vin "query"; select obj qry))

  -- regex (parity floor: Go stdlib regexp — see design/REGEX_API.md)
  rsT "regex.test" (getpropRaw regexs "test") (arg1 (\vin -> do p <- vget vin "pattern"; i <- vget vin "input"; re_test p i))
  rsT "regex.find" (getpropRaw regexs "find") (arg1 (\vin -> do p <- vget vin "pattern"; i <- vget vin "input"; re_find p i))
  rsT "regex.find_all" (getpropRaw regexs "find_all") (arg1 (\vin -> do p <- vget vin "pattern"; i <- vget vin "input"; re_find_all p i))
  rsT "regex.replace" (getpropRaw regexs "replace") (arg1 (\vin -> do p <- vget vin "pattern"; i <- vget vin "input"; r <- vget vin "replacement"; re_replace p i r))
  rsT "regex.escape" (getpropRaw regexs "escape") (arg1 (\vin -> do v <- vget vin "val"; re_escape v))

  rsF "sentinels.getprop_unify" (getpropRaw sentinels "getprop_unify") (arg1 (\vin -> do alt <- vget vin "alt"; val <- vget vin "val"; key <- vget vin "key"; getpropAlt alt val key))
  rsF "sentinels.getelem_absent" (getpropRaw sentinels "getelem_absent") (arg1 (\vin -> do alt <- vget vin "alt"; val <- vget vin "val"; key <- vget vin "key"; getelemAlt alt val key))
  rsF "sentinels.haskey_unify" (getpropRaw sentinels "haskey_unify") (arg1 (\vin -> do val <- vget vin "val"; key <- vget vin "key"; VBool <$> haskey val key))
  rsF "sentinels.isempty_unify" (getpropRaw sentinels "isempty_unify") (arg1 (\v -> VBool <$> isempty v))
  rsF "sentinels.isnode_unify" (getpropRaw sentinels "isnode_unify") (arg1 (\v -> return (VBool (isnode v))))
  rsF "sentinels.stringify_null" (getpropRaw sentinels "stringify_null") (arg1 (\vin -> VStr <$> stringify vin))

runWalkLog :: Counters -> String -> Value -> IO ()
runWalkLog c group node = do
  outcome <- try go :: IO (Either SomeException ())
  case outcome of
    Right () -> return ()
    Left err -> record c group False (O.errmessage err)
  where
    go = do
      testData <- clone node
      logRef <- emptyList
      let walklogA key v parent path = do
            ks <- if isNullish key then stringify VNoval else stringify key
            vs <- stringify v
            ps <- if isNullish parent then stringify VNoval else stringify parent
            ts <- pathify path
            sz <- size logRef
            _ <- setprop logRef (VNum (fromIntegral sz)) (VStr ("k=" ++ ks ++ ", v=" ++ vs ++ ", p=" ++ ps ++ ", t=" ++ ts))
            return v
      din <- getpropRaw testData "in"
      _ <- walk Nothing (Just walklogA) VNoval din
      dout <- getpropRaw testData "out"
      expected <- getprop dout (VStr "after")
      same <- eqv expected logRef
      if same then record c group True ""
      else do se <- stringify expected; sl <- stringify logRef; record c group False ("Expected: " ++ se ++ ", got: " ++ sl)

walkCopySubject :: Value -> IO Value
walkCopySubject vin = do
  curRef <- newIORef =<< mkList [VNoval]
  let walkcopy key v _parent path =
        if isNullish key then do
          inner <- if ismap v then emptyMap else if islist v then emptyList else return v
          nl <- mkList [inner]
          writeIORef curRef nl
          return v
        else do
          i <- size path
          nv <- if isnode v then do
                  cur <- readIORef curRef
                  let grow = do its <- listItems cur; when (length its <= i) (do _ <- setprop cur (VNum (fromIntegral (length its))) VNoval; grow)
                  grow
                  nn <- if ismap v then emptyMap else emptyList
                  _ <- setprop cur (VNum (fromIntegral i)) nn
                  return nn
                else return v
          cur <- readIORef curRef
          tgt <- getelem cur (VNum (fromIntegral (i - 1)))
          _ <- setprop tgt key nv
          return v
  _ <- walk (Just walkcopy) Nothing VNoval vin
  cur <- readIORef curRef
  getelem cur (VNum 0)

walkDepthSubject :: Value -> IO Value
walkDepthSubject vin = do
  topRef <- newIORef VNoval
  currRef <- newIORef VNoval
  let copy key v _parent _path = do
        if isNullish key || isnode v then do
          child <- if islist v then emptyList else emptyMap
          if isNullish key then do writeIORef topRef child; writeIORef currRef child
          else do cur <- readIORef currRef; _ <- setprop cur key child; writeIORef currRef child
        else do cur <- readIORef currRef; _ <- setprop cur key v; return ()
        return v
  src <- vget vin "src"; md <- vget vin "maxdepth"
  _ <- walk (Just copy) Nothing md src
  readIORef topRef
