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
import Data.List (intercalate, isInfixOf)
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hSetEncoding, stdout)

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
  -- The corpus is UTF-8 whatever the locale says, and a failure may print it.
  setLocaleEncoding utf8
  hSetEncoding stdout utf8
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
  condenses <- g "condense"
  let mg k = getpropRaw minor k
      rs group nd subj fl = do n <- nd; runSet c pack group n subj fl
      rsT group nd subj = rs group nd subj True
      rsF group nd subj = rs group nd subj False

  rsF "condense.condense" (getpropRaw condenses "condense") (arg1 condense)
  rsF "condense.expand" (getpropRaw condenses "expand") (arg1 expand)
  rsF "condense.iscondensed" (getpropRaw condenses "iscondensed") (arg1 (\v -> VBool <$> iscondensed v))
  runCondenseLocal c

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
  forM_ ["child", "exact"] $ \gn ->
    rsT ("validate." ++ gn) (getpropRaw validates gn) (arg1 (\vin -> do dat <- vget vin "data"; sp <- vget vin "spec"; validate INone dat sp))
  forM_ ["invalid", "directive", "nof", "all", "len", "range", "unknown"] $ \gn ->
    rsF ("validate." ++ gn) (getpropRaw validates gn) (arg1 (\vin -> do dat <- vget vin "data"; sp <- vget vin "spec"; validate INone dat sp))
  rsT "validate.special" (getpropRaw validates "special") (arg1 (\vin -> do
    dat <- vget vin "data"; sp <- vget vin "spec"; injm <- vget vin "inj"
    mt <- getprop injm (VStr "meta")
    let d = (defaultInjDef VNoval) { dMeta = mt }
    validate (if isNullish injm then INone else IDef d) dat sp))
  -- The corpus pins the message; this counts the errs, root forms included.
  runLocal c "validate.child-one-error-per-failure" $ do
    let x1 = O.JMap [("x", O.Num 1)]
        child = O.JMap [("`$CHILD`", O.Str "`$NUMBER`")]
        childl = O.JList [O.Str "`$CHILD`", O.Str "`$NUMBER`"]
    forM_ [(x1, O.JMap [("x", child)]), (x1, O.JMap [("x", childl)]), (O.Num 1, child), (O.Num 1, childl)] $ \(dj, sj) -> do
      dat <- tostruct dj
      sp <- tostruct sj
      errs <- emptyList
      _ <- validate (IDef (defaultInjDef errs)) dat sp
      n <- size errs
      shown <- compact errs
      expect (n == 1) shown

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

-- ---------------- condense: what the corpus cannot express ----------------

-- Identity, sharing and the immutability contract, as canonical's
-- `condense-*` tests check them.

expect :: Bool -> String -> IO ()
expect ok what = when (not ok) (ioError (userError what))

runLocal :: Counters -> String -> IO () -> IO ()
runLocal c group action = do
  outcome <- try action :: IO (Either SomeException ())
  case outcome of
    Right () -> record c group True ""
    Left err -> record c group False (show err)

raisesImmutable :: IO a -> IO Bool
raisesImmutable action = do
  outcome <- try action
  return (case outcome of
    Left (StructError message) -> "immutable" `isInfixOf` message
    Right _ -> False)

-- One node, not merely an equal one.
sameNode :: Value -> Value -> Bool
sameNode a b = case (a, b) of
  (VMap x, VMap y) -> x == y
  (VList x, VList y) -> x == y
  _ -> False

compact :: Value -> IO String
compact v = jm [VStr "indent", VNum 0] >>= jsonify v

nodeCount :: Value -> IO Int
nodeCount cd = getpropRaw cd "node" >>= size

isNum :: Double -> Value -> Bool
isNum n v = case v of
  VNum x -> x == n
  _ -> False

runCondenseLocal :: Counters -> IO ()
runCondenseLocal c = do
  let getm = O.JMap [("m", O.Str "GET")]
      mlist = O.JList [O.Num 1, O.Str "x", O.Bool True]
      strs = O.JList . map O.Str
      condensed j = tostruct j >>= condense

  runLocal c "condense.deterministic" $ do
    s1 <- condensed (O.JMap [("b", getm), ("a", getm), ("l", mlist)]) >>= compact
    s2 <- condensed (O.JMap [("b", getm), ("a", getm), ("l", mlist)]) >>= compact
    expect (s1 == s2) "condense is not deterministic"
    s3 <- condensed (O.JMap [("l", mlist), ("a", getm), ("b", getm)]) >>= compact
    expect (s1 == s3) "insertion order changed the bytes"

  runLocal c "condense.shares-identical-subtrees" $ do
    let xm = O.JMap [("m", O.Str "GET"), ("p", O.Str "/1")]
    one <- condensed (O.JMap [("x", xm)]) >>= nodeCount
    two <- condensed (O.JMap [("x", xm), ("y", xm)]) >>= nodeCount
    expect (two == one) "a second identical subtree added nodes"
    three <- condensed (O.JMap [("x", getm), ("y", O.JMap [("m", O.Str "PUT")]),
                                ("z", O.JMap [("m", O.Str "POST")])]) >>= nodeCount
    expect (three > two) "distinct subtrees added no nodes"

  runLocal c "condense.round-trips-by-value" $ do
    src <- tostruct (O.JMap [("a", O.JMap [("b", O.JList [O.Num 1, O.Str "x", O.Bool True, O.Null, O.JMap []])]),
                             ("c", O.Str "z")])
    back <- condense src >>= expand
    same <- eqv back src
    expect same "expand did not give back the value"

  runLocal c "condense.getpath-is-transparent" $ do
    src <- tostruct (O.JMap [("entity", O.JMap [("p", O.JMap [("op", O.JMap [("list",
             O.JMap [("method", O.Str "GET")])])])])])
    cd <- condense src
    path <- tostruct (strs ["entity", "p", "op", "list"])
    viaCondensed <- getpath INone cd path
    viaPlain <- getpath INone src path
    same <- eqv viaCondensed viaPlain
    expect same "a node read differs"
    leaf <- tostruct (strs ["entity", "p", "op", "list", "method"]) >>= getpath INone cd
    expect (vStrEq leaf "GET") "a leaf read differs"
    miss <- tostruct (strs ["entity", "nope"]) >>= getpath INone cd
    expect (isNoval miss) "a miss is not absent"

  runLocal c "condense.view-reads-without-materialising" $ do
    cd <- condensed (O.JMap [("entity", O.JMap [("a", O.JMap [("v", O.Num 1)]), ("b", O.JMap [("v", O.Num 2)])]),
                             ("other", O.Num 9)])
    v <- condenseview cd
    ks <- cvKeys v (VStr "entity")
    expect (ks == ["a", "b"]) "keys"
    got <- cvAt v (VStr "entity") >>= \e -> cvAt e (VStr "b") >>= \b -> cvGet b (VStr "v")
    expect (isNum 2 got) "at then get"
    hasA <- cvHas v (VStr "entity.a")
    expect hasA "has entity.a"
    hasZ <- cvHas v (VStr "entity.zz")
    expect (not hasZ) "has entity.zz"
    sz <- cvSize v
    expect (sz == 2) "size"

  runLocal c "condense.value-copies-and-ref-shares" $ do
    v <- condensed (O.JMap [("a", getm), ("b", getm)]) >>= condenseview
    -- a and b share one node; get must not let that be observed.
    x <- cvGet v (VStr "a")
    y <- cvGet v (VStr "b")
    same <- eqv x y
    expect same "a and b differ"
    expect (not (sameNode x y)) "get handed out one node twice"
    _ <- setprop x (VStr "m") (VStr "MUTATED")
    m <- cvGet v (VStr "b") >>= \b -> getprop b (VStr "m")
    expect (vStrEq m "GET") "a mutation reached another read"
    r1 <- cvAt v (VStr "a") >>= cvRef
    r2 <- cvAt v (VStr "a") >>= cvRef
    expect (sameNode r1 r2) "ref did not share"

  runLocal c "condense.preserves-proto-named-keys-and-values" $ do
    asValue <- tostruct (O.JMap [("x", O.Str "__proto__")])
    back <- condense asValue >>= expand
    same <- eqv back asValue
    expect same "a value named __proto__"
    s <- condensed (O.JMap [("__proto__", O.Num 1)]) >>= expand >>= compact
    expect (s == "{\"__proto__\":1}") "a key named __proto__"

  runLocal c "condense.getpath-matches-plain-on-null-and-options" $ do
    plain <- tostruct (O.JMap [("a", O.Null)])
    viaCondensed <- condense plain >>= \cd -> getpath INone cd (VStr "a")
    viaPlain <- getpath INone plain (VStr "a")
    expect (isNoval viaCondensed && isNoval viaPlain) "a stored null is not absent"
    store <- tostruct (O.JMap [("base", O.JMap [("x", O.Num 1)])])
    let d = (defaultInjDef VNoval) { dBase = VStr "base" }
    baseCondensed <- condense store >>= \cd -> getpath (IDef d) cd (VStr "x")
    basePlain <- getpath (IDef d) store (VStr "x")
    expect (isNum 1 baseCondensed && isNum 1 basePlain) "base was ignored"

  -- Unary + would accept these; an ordinary list lookup does not, so
  -- condensing must not change which value a path selects.
  runLocal c "condense.list-keys-are-canonical-integers" $ do
    plain <- tostruct (O.JMap [("l", O.JList [O.Num 10, O.Num 20])])
    cd <- condense plain
    forM_ ["01", "1e0", " 1", "+1", "1.0", "-0"] $ \k -> do
      path <- mkList [VStr "l", VStr k]
      viaCondensed <- getpath INone cd path
      viaPlain <- getpath INone plain path
      same <- eqv viaCondensed viaPlain
      expect same ("list key " ++ k)
    one <- mkList [VStr "l", VStr "1"] >>= getpath INone cd
    expect (isNum 20 one) "list key 1"

  runLocal c "condense.symbols-sort-by-code-point" $ do
    cd <- condensed (O.JMap [("a", O.Str "\x10000"), ("b", O.Str "\xFFFF")])
    sym <- getpropRaw cd "sym"
    syms <- listItems sym
    let position s = length (takeWhile (not . (`vStrEq` s)) syms)
    shown <- compact sym
    expect (position "\xFFFF" < position "\x10000")
      ("symbol table is not in code-point order: " ++ shown)

  runLocal c "condense.astral-keys-resolve" $ do
    cd <- condensed (O.JMap [("\xFF21", O.Num 1), ("\x1F600", O.Num 2)])
    astral <- mkList [VStr "\x1F600"] >>= getpath INone cd
    expect (isNum 2 astral) "the astral key"
    bmp <- mkList [VStr "\xFF21"] >>= getpath INone cd
    expect (isNum 1 bmp) "the BMP key"
    viaView <- condenseview cd >>= \v -> cvGet v (VStr "\x1F600")
    expect (isNum 2 viaView) "the astral key through a view"

  runLocal c "condense.invalid-key-mutations-stay-no-ops" $ do
    cd <- condensed (O.JMap [("a", O.Num 1)])
    d <- delprop cd VNoval
    expect (sameNode d cd) "delprop with an invalid key"
    s <- setprop cd VNoval (VNum 1)
    expect (sameNode s cd) "setprop with an invalid key"
    raised <- raisesImmutable (delprop cd (VStr "sym"))
    expect raised "a valid delprop did not raise"

  runLocal c "condense.is-immutable" $ do
    cd <- condensed (O.JMap [("a", O.Num 1)])
    viaSetpath <- raisesImmutable (setpath cd (VStr "a") (VNum 2))
    expect viaSetpath "setpath"
    viaSetprop <- raisesImmutable (setprop cd (VStr "a") (VNum 2))
    expect viaSetprop "setprop"
    viaDelprop <- raisesImmutable (delprop cd (VStr "sym"))
    expect viaDelprop "delprop"
    e <- expand cd
    _ <- setpath e (VStr "a") (VNum 2)
    a <- getprop e (VStr "a")
    expect (isNum 2 a) "the expanded copy is not mutable"

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
