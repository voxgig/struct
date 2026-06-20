-- Test runner for the shared JSON corpus (build/test/test.json).
-- Self-contained: an in-tree JSON reader builds the library's `Value` type
-- directly (via the IORef-backed nodes), so the Haskell port is exercised
-- exactly as in production. The runner logic mirrors every other port.

{-# LANGUAGE LambdaCase #-}

module Main where

import Control.Exception (SomeException, throwIO, try)
import Control.Monad (forM_, when)
import Data.Char (chr, toLower)
import Data.IORef
import Data.List (intercalate, isPrefixOf)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import Numeric (readHex)

import VoxgigStruct
import qualified Vregex

nullmark, undefmark, existsmark :: String
nullmark = "__NULL__"
undefmark = "__UNDEF__"
existsmark = "__EXISTS__"

-- ---------------- JSON reader -> Value ----------------

jsonRead :: String -> IO Value
jsonRead s0 = do
  posRef <- newIORef 0
  let arr = s0
      n = length arr
      at i = arr !! i
      peek = do p <- readIORef posRef; return (if p < n then Just (at p) else Nothing)
      adv = modifyIORef' posRef (+ 1)
      skipWs = do
        p <- readIORef posRef
        if p < n && (at p `elem` " \t\n\r") then adv >> skipWs else return ()
      pval = do
        skipWs
        mc <- peek
        case mc of
          Just '{' -> pobj
          Just '[' -> parr
          Just '"' -> VStr <$> pstr
          Just 't' -> modifyIORef' posRef (+ 4) >> return (VBool True)
          Just 'f' -> modifyIORef' posRef (+ 5) >> return (VBool False)
          Just 'n' -> modifyIORef' posRef (+ 4) >> return VNull
          _ -> pnum
      pobj = do
        adv; skipWs
        mc <- peek
        if mc == Just '}' then adv >> emptyMap
        else do
          m <- emptyMap
          let loop = do
                skipWs
                k <- pstr
                skipWs; adv  -- ':'
                v <- pval
                _ <- setprop m (VStr k) v
                skipWs
                c <- peek >>= \case Just c -> adv >> return c; Nothing -> return '}'
                if c == ',' then loop else return m
          loop
      parr = do
        adv; skipWs
        mc <- peek
        if mc == Just ']' then adv >> emptyList
        else do
          accRef <- newIORef []
          let loop = do
                v <- pval
                modifyIORef' accRef (v :)
                skipWs
                c <- peek >>= \case Just c -> adv >> return c; Nothing -> return ']'
                if c == ',' then loop else do acc <- readIORef accRef; mkList (reverse acc)
          loop
      pstr = do
        adv  -- opening quote
        bRef <- newIORef []
        let loop = do
              p <- readIORef posRef
              let c = at p
              adv
              if c == '"' then do b <- readIORef bRef; return (reverse b)
              else if c == '\\' then do
                p2 <- readIORef posRef
                let e = at p2
                adv
                case e of
                  '"' -> push '"' >> loop
                  '\\' -> push '\\' >> loop
                  '/' -> push '/' >> loop
                  'n' -> push '\n' >> loop
                  't' -> push '\t' >> loop
                  'r' -> push '\r' >> loop
                  'b' -> push '\b' >> loop
                  'f' -> push '\f' >> loop
                  'u' -> do
                    pp <- readIORef posRef
                    let hex = take 4 (drop pp arr)
                    modifyIORef' posRef (+ 4)
                    case readHex hex of [(code, _)] -> push (chr code) >> loop; _ -> loop
                  _ -> push e >> loop
              else push c >> loop
            push c = modifyIORef' bRef (c :)
        loop
      pnum = do
        start <- readIORef posRef
        let go = do
              p <- readIORef posRef
              if p < n && (at p `elem` "0123456789-+.eE") then adv >> go else return ()
        go
        end <- readIORef posRef
        let tok = take (end - start) (drop start arr)
        return (VNum (read tok))
  pval

-- ---------------- fixJSON / equality ----------------

fixJson :: Value -> Bool -> IO Value
fixJson v flagNull = case v of
  VNoval -> return (if flagNull then VStr nullmark else v)
  VNull -> return (if flagNull then VStr nullmark else v)
  VMap m -> do
    es <- readIORef m
    o <- emptyMap
    forM_ es $ \(k, x) -> do fx <- fixJson x flagNull; _ <- setprop o (VStr k) fx; return ()
    return o
  VList r -> do its <- readIORef r; xs <- mapM (\x -> fixJson x flagNull) its; mkList xs
  _ -> return v

eqv :: Value -> Value -> IO Bool
eqv a b = case (a, b) of
  (VNoval, VNoval) -> return True
  (VNoval, VNull) -> return True
  (VNull, VNoval) -> return True
  (VNull, VNull) -> return True
  (VBool x, VBool y) -> return (x == y)
  (VNum x, VNum y) -> return (x == y)
  (VStr x, VStr y) -> return (x == y)
  (VList x, VList y) -> do
    xs <- readIORef x; ys <- readIORef y
    if length xs /= length ys then return False else allM (zipWith eqv xs ys)
  (VMap x, VMap y) -> do
    xs <- readIORef x; ys <- readIORef y
    if length xs /= length ys then return False
    else allM [case lookup k ys of Just w -> eqv v w; Nothing -> return False | (k, v) <- xs]
  _ -> return (sameRef a b)
  where
    allM = andM
    sameRef (VList p) (VList q) = p == q
    sameRef (VMap p) (VMap q) = p == q
    sameRef VNoval VNoval = True
    sameRef _ _ = False

-- ---------------- match support ----------------

containsLower :: String -> String -> Bool
containsLower hay needle =
  let h = map toLower hay; nd = map toLower needle
  in null nd || go h
  where
    go [] = False
    go s@(_:rest) = (map toLower needle `isPrefixOf` map toLower s) || go rest

matchval :: Value -> Value -> IO Bool
matchval check0 base = do
  let check = if vStrEq check0 undefmark || vStrEq check0 nullmark then VNoval else check0
  e <- eqv check base
  if e then return True
  else case check of
    VStr cs -> do
      basestr <- stringify base
      if length cs >= 2 && head cs == '/' && last cs == '/'
        then return (Vregex.testStr (take (length cs - 2) (drop 1 cs)) basestr)
        else do cstr <- stringify check; return (containsLower basestr cstr)
    VFunc _ -> return True
    _ -> return False

doMatch :: Value -> Value -> IO ()
doMatch check base0 = do
  base <- clone base0
  _ <- walk (Just (\_ v _ path -> do
    when (not (isnode v)) $ do
      baseval <- getpath INone base path
      e <- eqv baseval v
      if e then return ()
      else if vStrEq v undefmark && isNullish baseval then return ()
      else if vStrEq v existsmark && not (isNullish baseval) then return ()
      else do
        mv <- matchval v baseval
        if not mv then do
          pelems <- listItems path
          pstrs <- mapM jsString pelems
          sv <- stringify v
          sb <- stringify baseval
          ioError (userError ("MATCH: " ++ intercalate "." pstrs ++ ": [" ++ sv ++ "] <=> [" ++ sb ++ "]"))
        else return ()
    return v)) Nothing VNoval check
  return ()

-- ---------------- result tracking ----------------

data Counters = Counters { npass :: IORef Int, nfail :: IORef Int, failures :: IORef [String] }

record :: Counters -> String -> String -> Bool -> String -> IO ()
record c group name ok msg =
  if ok then modifyIORef' (npass c) (+ 1)
  else do modifyIORef' (nfail c) (+ 1); modifyIORef' (failures c) (++ ["FAIL " ++ group ++ " " ++ name ++ " - " ++ msg])

errMsg :: SomeException -> String
errMsg e = case lines (show e) of (l:_) -> stripUser l; [] -> show e
  where stripUser s = case dropWhile (/= ':') s of _ -> s

-- ---------------- per-entry runner ----------------

omapV :: [(String, Value)] -> IO Value
omapV = mkMap

entryGet :: Value -> String -> IO Value
entryGet e k = getpropRaw e k

entryHas :: Value -> String -> IO Bool
entryHas e k = case e of { VMap m -> do { es <- readIORef m; return (any ((== k) . fst) es) }; _ -> return False }

resolveArgs :: Value -> IO [Value]
resolveArgs entry = do
  hc <- entryHas entry "ctx"
  if hc then do c <- entryGet entry "ctx"; return [c]
  else do
    ha <- entryHas entry "args"
    if ha then do a <- entryGet entry "args"; if islist a then listItems a else return []
    else do
      hi <- entryHas entry "in"
      if hi then do v <- entryGet entry "in"; c <- clone v; return [c]
      else return [VNoval]

checkResult :: Value -> [Value] -> Value -> IO ()
checkResult entry args res = do
  hm <- entryHas entry "match"
  matched <- if hm then do
      mv <- entryGet entry "match"
      ein <- entryGet entry "in"; eres <- entryGet entry "res"; ectx <- entryGet entry "ctx"
      al <- mkList args
      o <- omapV [("in", ein), ("args", al), ("out", eres), ("ctx", ectx)]
      doMatch mv o
      return True
    else return False
  out <- entryGet entry "out"
  e <- eqv out res
  if e then return ()
  else if matched && (vStrEq out nullmark || isNullish out) then return ()
  else do so <- stringify out; sr <- stringify res; ioError (userError ("Expected: " ++ so ++ ", got: " ++ sr))

handleError :: Value -> SomeException -> IO ()
handleError entry err = do
  let msg = exMsg err
  he <- entryHas entry "err"
  if he then do
    entryErr <- entryGet entry "err"
    em <- matchval entryErr (VStr msg)
    if vIsTrue entryErr || em then do
      hm <- entryHas entry "match"
      when hm $ do
        mv <- entryGet entry "match"
        ein <- entryGet entry "in"; eres <- entryGet entry "res"; ectx <- entryGet entry "ctx"
        o <- omapV [("in", ein), ("out", eres), ("ctx", ectx), ("err", VStr msg)]
        doMatch mv o
    else do se <- stringify entryErr; ioError (userError ("ERROR MATCH: [" ++ se ++ "] <=> [" ++ msg ++ "]"))
  else throwIO err

exMsg :: SomeException -> String
exMsg e =
  let s = show e
  in case stripPrefix "user error (" s of
       Just rest -> reverse (drop 1 (reverse rest))  -- drop trailing ')'
       Nothing -> s
  where stripPrefix p str = if p `isPrefixOf` str then Just (drop (length p) str) else Nothing

runSet :: Counters -> String -> Value -> ([Value] -> IO Value) -> Bool -> IO ()
runSet c group node subject flagNull = do
  fixed <- fixJson node flagNull
  testset <- getprop fixed (VStr "set") >>= \ts -> if islist ts then listItems ts else return []
  forM_ testset $ \entry -> do
    nm <- entryGet entry "name" >>= jsString
    result <- try (runOne entry) :: IO (Either SomeException ())
    case result of
      Right () -> record c group nm True ""
      Left e -> do
        r2 <- try (handleError entry e) :: IO (Either SomeException ())
        case r2 of
          Right () -> record c group nm True ""
          Left e2 -> record c group nm False (exMsg e2)
  where
    runOne entry = do
      ho <- entryHas entry "out"
      when (not ho && flagNull) $ do _ <- setprop entry (VStr "out") (VStr nullmark); return ()
      args <- resolveArgs entry
      r <- subject args
      res <- fixJson r flagNull
      _ <- setprop entry (VStr "res") res
      checkResult entry args res

runSingle :: Counters -> String -> Value -> (Value -> IO Value) -> IO ()
runSingle c group node actualFn = do
  result <- try go :: IO (Either SomeException ())
  case result of
    Right () -> return ()
    Left e -> record c group "single" False (exMsg e)
  where
    go = do
      expected <- entryGet node "out"
      inv <- entryGet node "in"
      actual <- actualFn inv
      e <- eqv expected actual
      if e then record c group "single" True ""
      else do se <- stringify expected; sa <- stringify actual; record c group "single" False ("Expected: " ++ se ++ ", got: " ++ sa)

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
  args <- getArgs
  let testfile = case args of (f:_) -> f; [] -> "../build/test/test.json"
  raw <- readFile testfile
  alltests <- jsonRead raw
  spec <- entryGet alltests "struct"
  c <- Counters <$> newIORef 0 <*> newIORef 0 <*> newIORef []
  runAll c spec
  fs <- readIORef (failures c)
  forM_ fs putStrLn
  p <- readIORef (npass c)
  f <- readIORef (nfail c)
  putStrLn ("\nPASS " ++ show p ++ "  FAIL " ++ show f)
  when (f > 0) exitFailure

-- ---------------- test groups ----------------

nullModifier :: Value -> Value -> Value -> Inj -> IO ()
nullModifier v key parent _inj =
  if vStrEq v nullmark then setprop parent key VNull >> return ()
  else case v of
    VStr s -> do _ <- setprop parent key (VStr (replaceAll s nullmark "null")); return ()
    _ -> return ()

runAll :: Counters -> Value -> IO ()
runAll c spec = do
  let g k = getpropRaw spec k
  minor <- g "minor"; walks <- g "walk"; merges <- g "merge"
  getpaths <- g "getpath"; injects <- g "inject"; transforms <- g "transform"
  validates <- g "validate"; selects <- g "select"; sentinels <- g "sentinels"
  let mg k = getpropRaw minor k
      rs group nd subj fl = do n <- nd; runSet c group n subj fl
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
  rsF "minor.getprop" (mg "getprop") (arg1 (\vin -> do
    alt <- vget vin "alt"; val <- vget vin "val"; key <- vget vin "key"
    if isNullish alt then getprop val key else getpropAlt alt val key))
  rsT "minor.setprop" (mg "setprop") (arg1 (\vin -> do p <- vget vin "parent"; k <- vget vin "key"; val <- vget vin "val"; setprop p k val))
  rsF "minor.haskey" (mg "haskey") (arg1 (\vin -> do s <- vget vin "src"; k <- vget vin "key"; VBool <$> haskey s k))
  rsT "minor.keysof" (mg "keysof") (arg1 (\v -> do ks <- keysof v; mkList (map VStr ks)))
  rsF "minor.join" (mg "join") (arg1 (\vin -> do val <- vget vin "val"; sep <- vget vin "sep"; url <- vget vin "url"; VStr <$> join val sep (vIsTrue url)))
  rsF "minor.typify" (mg "typify") (arg1 (\v -> return (vint (typify v))))
  rsF "minor.setpath" (mg "setpath") (arg1 (\vin -> do st <- vget vin "store"; pth <- vget vin "path"; val <- vget vin "val"; setpath st pth val))
  rsT "minor.filter" (mg "filter") (arg1 (\vin -> do
    val <- vget vin "val"; ch <- vget vin "check"
    let check = case ch of
          VStr "gt3" -> \(_, x) -> case x of VNum n -> n > 3; _ -> False
          VStr "lt3" -> \(_, x) -> case x of VNum n -> n < 3; _ -> False
          _ -> \_ -> False
    VoxgigStruct.filter val check))
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
    store <- omapV [("$TOP", stv), ("$FOO", VFunc (\_ _ _ _ -> return (VStr "foo")))]
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

  rsF "sentinels.getprop_unify" (getpropRaw sentinels "getprop_unify") (arg1 (\vin -> do alt <- vget vin "alt"; val <- vget vin "val"; key <- vget vin "key"; getpropAlt alt val key))
  rsF "sentinels.getelem_absent" (getpropRaw sentinels "getelem_absent") (arg1 (\vin -> do alt <- vget vin "alt"; val <- vget vin "val"; key <- vget vin "key"; getelemAlt alt val key))
  rsF "sentinels.haskey_unify" (getpropRaw sentinels "haskey_unify") (arg1 (\vin -> do val <- vget vin "val"; key <- vget vin "key"; VBool <$> haskey val key))
  rsF "sentinels.isempty_unify" (getpropRaw sentinels "isempty_unify") (arg1 (\v -> VBool <$> isempty v))
  rsF "sentinels.isnode_unify" (getpropRaw sentinels "isnode_unify") (arg1 (\v -> return (VBool (isnode v))))
  rsF "sentinels.stringify_null" (getpropRaw sentinels "stringify_null") (arg1 (\vin -> VStr <$> stringify vin))

runWalkLog :: Counters -> String -> Value -> IO ()
runWalkLog c group node = do
  result <- try go :: IO (Either SomeException ())
  case result of
    Right () -> return ()
    Left e -> record c group "log" False (exMsg e)
  where
    go = do
      testData <- clone node
      logRef <- emptyList
      let walklog _ v _ _ = return v
          walklogA key v parent path = do
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
      e <- eqv expected logRef
      if e then record c group "log" True ""
      else do se <- stringify expected; sl <- stringify logRef; record c group "log" False ("Expected: " ++ se ++ ", got: " ++ sl)

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
