-- Test Provider (prototype) — Haskell port of the canonical ts/provider.ts.
--
-- Reads the shared corpus (build/test/test.json) and hands test code clean,
-- normalized cases. It is NOT a test runner: it never calls the subject and
-- never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
--
-- DEPENDENCY-FREE: GHC base only. The JSON reader is self-contained (adapted
-- from haskell/test/Runner.hs), producing an order-preserving `Json` type
-- whose objects are association lists.
--
-- NOTE: GHC is unavailable in this environment, so this file has NOT been
-- compiled or executed. It is a faithful port written from the canonical
-- TypeScript source and the PROVIDER.md spec.

{-# LANGUAGE LambdaCase #-}

module Provider
  ( Json(..)
  , Provider
  , Entry(..)
  , Input(..)
  , InputKind(..)
  , Expect(..)
  , ExpectKind(..)
  , ErrorCheck(..)
  , MatchResult(..)
  , parseJson
  , load
  , raw
  , functions
  , groups
  , entries
  , stringify
  , matchval
  , equal
  , equalStrict
  , structMatch
  , errorMatches
  ) where

import Data.Char (chr, toLower)
import Data.IORef
import Data.List (isInfixOf)
import Numeric (readHex, showHex)
import System.IO.Unsafe (unsafePerformIO)

-- ─── JSON model ─────────────────────────────────────────────────────────────
-- JObj is an association list to preserve key order (mirrors JSON.parse order
-- preservation and the runner's order-preserving maps).

data Json
  = JNull
  | JBool Bool
  | JNum Double
  | JStr String
  | JArr [Json]
  | JObj [(String, Json)]
  deriving (Show)

-- Reference equality for the model: structural, order-insensitive for objects
-- (object equality compares by key membership, matching deepEq in the canon).
instance Eq Json where
  JNull        == JNull        = True
  (JBool a)    == (JBool b)    = a == b
  (JNum a)     == (JNum b)     = a == b
  (JStr a)     == (JStr b)     = a == b
  (JArr a)     == (JArr b)     = length a == length b && and (zipWith (==) a b)
  (JObj a)     == (JObj b)     =
    length a == length b
      && all (\(k, v) -> case lookup k b of Just w -> v == w; Nothing -> False) a
  _            == _            = False

-- ─── Sentinels ──────────────────────────────────────────────────────────────

nullmark, undefmark, existsmark :: String
nullmark = "__NULL__"
undefmark = "__UNDEF__"
existsmark = "__EXISTS__"

-- ─── JSON parser ────────────────────────────────────────────────────────────
-- Adapted from haskell/test/Runner.hs's IORef-backed reader, retargeted at the
-- pure order-preserving `Json` type. Handles escapes/\uXXXX, numbers,
-- true/false/null. Uses an IORef cursor over the input held in unsafePerformIO
-- so the public surface stays pure.

parseJson :: String -> Json
parseJson s0 = unsafePerformIO (jsonRead s0)
{-# NOINLINE parseJson #-}

jsonRead :: String -> IO Json
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
          Just '"' -> JStr <$> pstr
          Just 't' -> modifyIORef' posRef (+ 4) >> return (JBool True)
          Just 'f' -> modifyIORef' posRef (+ 5) >> return (JBool False)
          Just 'n' -> modifyIORef' posRef (+ 4) >> return JNull
          _        -> pnum
      pobj = do
        adv; skipWs
        mc <- peek
        if mc == Just '}' then adv >> return (JObj [])
        else do
          accRef <- newIORef []
          let loop = do
                skipWs
                k <- pstr
                skipWs; adv  -- ':'
                v <- pval
                modifyIORef' accRef ((k, v) :)
                skipWs
                c <- peek >>= \case Just ch -> adv >> return ch; Nothing -> return '}'
                if c == ',' then loop
                else do acc <- readIORef accRef; return (JObj (reverse acc))
          loop
      parr = do
        adv; skipWs
        mc <- peek
        if mc == Just ']' then adv >> return (JArr [])
        else do
          accRef <- newIORef []
          let loop = do
                v <- pval
                modifyIORef' accRef (v :)
                skipWs
                c <- peek >>= \case Just ch -> adv >> return ch; Nothing -> return ']'
                if c == ',' then loop
                else do acc <- readIORef accRef; return (JArr (reverse acc))
          loop
      pstr = do
        adv  -- opening quote
        bRef <- newIORef []
        let push c = modifyIORef' bRef (c :)
            loop = do
              p <- readIORef posRef
              let c = at p
              adv
              if c == '"' then do b <- readIORef bRef; return (reverse b)
              else if c == '\\' then do
                p2 <- readIORef posRef
                let e = at p2
                adv
                case e of
                  '"'  -> push '"' >> loop
                  '\\' -> push '\\' >> loop
                  '/'  -> push '/' >> loop
                  'n'  -> push '\n' >> loop
                  't'  -> push '\t' >> loop
                  'r'  -> push '\r' >> loop
                  'b'  -> push '\b' >> loop
                  'f'  -> push '\f' >> loop
                  'u'  -> do
                    pp <- readIORef posRef
                    let hex = take 4 (drop pp arr)
                    modifyIORef' posRef (+ 4)
                    case readHex hex of
                      [(code, _)] -> push (chr code) >> loop
                      _           -> loop
                  _    -> push e >> loop
              else push c >> loop
        loop
      pnum = do
        start <- readIORef posRef
        let go = do
              p <- readIORef posRef
              if p < n && (at p `elem` "0123456789-+.eE") then adv >> go else return ()
        go
        end <- readIORef posRef
        let tok = take (end - start) (drop start arr)
        return (JNum (read tok))
  pval

-- ─── Provider ───────────────────────────────────────────────────────────────

newtype Provider = Provider { spec :: Json }

-- Default corpus path: build/test/test.json relative to the repo root.
-- This file lives at test/proto/haskell, so the repo root is three levels up.
defaultTestFile :: FilePath
defaultTestFile = "../../../build/test/test.json"

load :: Maybe FilePath -> IO Provider
load mfile = do
  let file = maybe defaultTestFile id mfile
  contents <- readFile file
  parsed <- jsonRead contents
  return (Provider parsed)

raw :: Provider -> Json
raw = spec

-- The root used for function discovery: spec.struct if present, else spec.
specRoot :: Provider -> Json
specRoot p = case objLookup (spec p) "struct" of
  Just node -> node
  Nothing   -> spec p

fnNode :: Provider -> String -> Json
fnNode p fn =
  case objLookup (spec p) "struct" >>= \root -> objLookup root fn of
    Just node -> node
    Nothing   -> case objLookup (spec p) fn of
      Just node -> node
      Nothing   -> error ("Unknown function: " ++ fn)

functions :: Provider -> [String]
functions p =
  case specRoot p of
    JObj kvs -> [k | (k, v) <- kvs, isGroupBag v || hasGroups v]
    _        -> []

groups :: Provider -> String -> [String]
groups p fn =
  case fnNode p fn of
    JObj kvs -> [k | (k, v) <- kvs, k /= "name", isGroupBag v]
    _        -> []

entries :: Provider -> String -> Maybe String -> [Entry]
entries p fn mgroup =
  let node = fnNode p fn
      gs = maybe (groups p fn) (: []) mgroup
      collect g =
        case objLookup node g of
          Just bag | isGroupBag bag ->
            case objLookup bag "set" of
              Just (JArr items) -> zipWith (normalize fn g) [0 ..] items
              _                 -> []
          _ -> []
  in concatMap collect gs

-- A group bag is an object with a `set` array.
isGroupBag :: Json -> Bool
isGroupBag v = case v of
  JObj kvs -> case lookup "set" kvs of Just (JArr _) -> True; _ -> False
  _        -> False

-- A function node has at least one child group bag.
hasGroups :: Json -> Bool
hasGroups v = case v of
  JObj kvs -> any (\(k, x) -> k /= "name" && isGroupBag x) kvs
  _        -> False

-- ─── Entry model ────────────────────────────────────────────────────────────

data InputKind = KIn | KArgs | KCtx deriving (Eq, Show)

data Input = Input
  { ikind  :: InputKind
  , ivalue :: Json
  } deriving (Show)

data ExpectKind = EValue | EError | EMatch | EAbsent deriving (Eq, Show)

data ErrorCheck = ErrorCheck
  { anyErr :: Bool
  , etext  :: Maybe String
  , eregex :: Bool
  } deriving (Show)

data Expect = Expect
  { ekind  :: ExpectKind
  , evalue :: Maybe Json
  , eerror :: Maybe ErrorCheck
  , ematch :: Maybe Json
  } deriving (Show)

data Entry = Entry
  { function :: String
  , group    :: String
  , index    :: Int
  , eid      :: Maybe String
  , doc      :: Bool
  , client   :: Maybe String
  , input    :: Input
  , expect   :: Expect
  , eraw     :: Json
  } deriving (Show)

-- ─── Normalization (exactly per PROVIDER.md) ───────────────────────────────

-- Object key lookup preserving order semantics; Nothing when key absent.
objLookup :: Json -> String -> Maybe Json
objLookup (JObj kvs) k = lookup k kvs
objLookup _ _          = Nothing

-- Key presence on an object (the assoc-list keys), NOT a null-check.
objHas :: Json -> String -> Bool
objHas (JObj kvs) k = any ((== k) . fst) kvs
objHas _ _          = False

normalize :: String -> String -> Int -> Json -> Entry
normalize fn g idx rawEntry = Entry
  { function = fn
  , group    = g
  , index    = idx
  , eid      = case objLookup rawEntry "id" of
                 Just v | not (isNullJson v) -> Just (jsonToString v)
                 _                           -> Nothing
  , doc      = case objLookup rawEntry "doc" of Just (JBool True) -> True; _ -> False
  , client   = case objLookup rawEntry "client" of
                 Just v | not (isNullJson v) -> Just (jsonToString v)
                 _                           -> Nothing
  , input    = resolveInput rawEntry
  , expect   = resolveExpect rawEntry
  , eraw     = rawEntry
  }
  where
    isNullJson JNull = True
    isNullJson _     = False
    -- id/client are coerced to string (mirrors String(raw.id)); for the corpus
    -- these are already strings.
    jsonToString (JStr s) = s
    jsonToString v        = stringify v

resolveInput :: Json -> Input
resolveInput rawEntry
  | objHas rawEntry "ctx"  = Input KCtx  (must "ctx")
  | objHas rawEntry "args" = Input KArgs (must "args")
  | otherwise              = Input KIn  (if objHas rawEntry "in" then must "in" else JNull)
  where
    must k = maybe JNull id (objLookup rawEntry k)

parseErr :: Json -> ErrorCheck
parseErr err = case err of
  JBool True -> ErrorCheck True Nothing False
  JStr s     -> case regexInner s of
                  Just inner -> ErrorCheck False (Just inner) True
                  Nothing    -> ErrorCheck False (Just s) False
  -- Non-true, non-string err spec: treat as "any error".
  _          -> ErrorCheck True Nothing False

-- Match "/…/" — leading and trailing slash with at least one inner char.
regexInner :: String -> Maybe String
regexInner s
  | length s >= 3 && head s == '/' && last s == '/' =
      Just (take (length s - 2) (drop 1 s))
  | otherwise = Nothing

resolveExpect :: Json -> Expect
resolveExpect rawEntry
  | objHas rawEntry "err" =
      Expect EError Nothing (Just (parseErr (forceLookup "err"))) matchPart
  | objHas rawEntry "out" =
      Expect EValue (Just (forceLookup "out")) Nothing matchPart
  | objHas rawEntry "match" =
      Expect EMatch Nothing Nothing (Just (forceLookup "match"))
  | otherwise =
      Expect EAbsent Nothing Nothing Nothing
  where
    matchPart = if objHas rawEntry "match" then objLookup rawEntry "match" else Nothing
    forceLookup k = maybe JNull id (objLookup rawEntry k)

-- ─── Pure comparison helpers (PROVIDER.md §5) ──────────────────────────────

-- stringify(x) = the string if it is already a string, else compact JSON.
stringify :: Json -> String
stringify (JStr s) = s
stringify v        = compactJson v

compactJson :: Json -> String
compactJson v = case v of
  JNull    -> "null"
  JBool b  -> if b then "true" else "false"
  JNum d   -> showNum d
  JStr s   -> showJsonString s
  JArr xs  -> "[" ++ intercalate "," (map compactJson xs) ++ "]"
  JObj kvs -> "{" ++ intercalate "," (map kv kvs) ++ "}"
  where
    kv (k, x) = showJsonString k ++ ":" ++ compactJson x

-- Compact number rendering close to JSON: integral doubles print without a
-- trailing ".0" (mirrors JSON.stringify).
showNum :: Double -> String
showNum d
  | isNaN d || isInfinite d = "null"
  | d == fromIntegral i     = show i
  | otherwise               = show d
  where i = round d :: Integer

showJsonString :: String -> String
showJsonString s = "\"" ++ concatMap esc s ++ "\""
  where
    esc c = case c of
      '"'  -> "\\\""
      '\\' -> "\\\\"
      '\n' -> "\\n"
      '\t' -> "\\t"
      '\r' -> "\\r"
      '\b' -> "\\b"
      '\f' -> "\\f"
      _ | c < ' ' -> "\\u" ++ pad4 (showHex (fromEnum c) "")
        | otherwise -> [c]
    pad4 h = replicate (4 - length h) '0' ++ h

intercalate :: String -> [String] -> String
intercalate _ []     = ""
intercalate _ [x]    = x
intercalate sep (x:xs) = x ++ sep ++ intercalate sep xs

-- normNull: __NULL__ → null, recurse through arrays/objects (mirrors normNull).
normNull :: Json -> Json
normNull x = case x of
  JStr s | s == nullmark -> JNull
  JArr xs                -> JArr (map normNull xs)
  JObj kvs               -> JObj [(k, normNull v) | (k, v) <- kvs]
  _                      -> x

-- normMark: only __NULL__ → null (strict variant).
normMark :: Json -> Json
normMark x = case x of
  JStr s | s == nullmark -> JNull
  JArr xs                -> JArr (map normMark xs)
  JObj kvs               -> JObj [(k, normMark v) | (k, v) <- kvs]
  _                      -> x

-- matchval(check, base): check == base; else if check is a string:
--   "/re/" ⇒ regex test over stringify(base) (PROTOTYPE: regex simplified),
--   otherwise stringify(base) contains check, case-insensitively.
-- (No function case in the Json model — JFunc does not exist here.)
matchval :: Json -> Json -> Bool
matchval check base
  | check == base = True
  | otherwise = case check of
      JStr cs ->
        let basestr = stringify base
        in case regexInner cs of
             Just re -> regexLike re basestr
             Nothing -> map toLower cs `isInfixOf` map toLower basestr
      _ -> False

-- PROTOTYPE: regex simplified. `base` has no regex engine; we approximate a
-- "/re/" check by case-sensitive substring containment of the inner pattern.
-- This is intentionally weaker than a real RegExp and is documented as such.
regexLike :: String -> String -> Bool
regexLike re hay = re `isInfixOf` hay

equal :: Json -> Json -> Bool
equal expected actual = deepEq (normNull expected) (normNull actual)

equalStrict :: Json -> Json -> Bool
equalStrict expected actual = deepEq (normMark expected) (normMark actual)

-- deepEq mirrors the canonical deepEq: arrays by length+elementwise; objects by
-- key count + membership; primitives by value. (Eq Json already implements
-- these semantics, including bool/number distinction via constructors.)
deepEq :: Json -> Json -> Bool
deepEq = (==)

errorMatches :: ErrorCheck -> String -> Bool
errorMatches check message
  | anyErr check = True
  | otherwise = case etext check of
      Nothing   -> False
      Just text ->
        if eregex check
          then regexLike text message               -- PROTOTYPE: regex simplified
          else map toLower text `isInfixOf` map toLower message

-- ─── structMatch ────────────────────────────────────────────────────────────

data MatchResult = MatchResult
  { ok        :: Bool
  , mpath     :: [String]
  , mexpected :: Maybe Json
  , mactual   :: Maybe Json
  } deriving (Show)

okResult :: MatchResult
okResult = MatchResult True [] Nothing Nothing

-- Partial structural match: every leaf of `check` must match `base` at its path.
-- Mirrors the canonical structMatch, with `__UNDEF__` requiring absence and
-- `__EXISTS__` requiring presence. First failure returns its path + values.
structMatch :: Json -> Json -> MatchResult
structMatch check base = go (walkLeaves check [])
  where
    go [] = okResult
    go ((val, path) : rest) =
      let baseval = getpath base path  -- Maybe Json; Nothing == undefined/absent
      in if leafOk val baseval
           then go rest
           else MatchResult False path (Just val) baseval
    leafOk val baseval =
      case baseval of
        Just bv | val == bv -> True
        _ ->
          case val of
            JStr s | s == undefmark -> baseval == Nothing
            JStr s | s == existsmark ->
              case baseval of Just bv -> not (isNullJson bv); Nothing -> False
            _ -> matchval val (maybe JNull id baseval)
    isNullJson JNull = True
    isNullJson _     = False

-- Walk to leaves, collecting (leafValue, path). Objects and non-empty arrays
-- recurse; scalars (and—per the canonical isNode—nulls/bools/numbers/strings)
-- are leaves. Empty containers are NOT leaves (matching walkLeaves: an empty
-- object/array yields no leaves), consistent with the canon.
walkLeaves :: Json -> [String] -> [(Json, [String])]
walkLeaves node path = case node of
  JArr xs  -> concat (zipWith (\i v -> walkLeaves v (path ++ [show i])) [0 :: Int ..] xs)
  JObj kvs -> concatMap (\(k, v) -> walkLeaves v (path ++ [k])) kvs
  _        -> [(node, path)]

-- getpath over the Json model: Nothing means undefined (absent or off the end).
getpath :: Json -> [String] -> Maybe Json
getpath store [] = Just store
getpath store (key : rest) = case store of
  JNull   -> Nothing
  JArr xs -> case readIndex key of
               Just i | i >= 0 && i < length xs -> getpath (xs !! i) rest
               _                                -> Nothing
  JObj kvs -> case lookup key kvs of
                Just v  -> getpath v rest
                Nothing -> Nothing
  _ -> Nothing

readIndex :: String -> Maybe Int
readIndex s = case reads s of [(i, "")] -> Just i; _ -> Nothing
