-- Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.

{-# LANGUAGE LambdaCase #-}

-- |
-- Module      : VoxgigStruct
-- Copyright   : (c) 2025-2026 Voxgig Ltd.
-- License     : MIT
-- Maintainer  : richard.rodger\@voxgig.com
-- Stability   : experimental
--
-- Utilities for walking, merging, transforming, injecting into and validating
-- JSON-like data structures — the Haskell port of the canonical
-- @voxgig\/struct@ library (TypeScript @typescript\/src\/StructUtility.ts@).
--
-- Values are modelled by the 'Value' type. Like the canonical TypeScript (and
-- the OCaml \/ Rust ports) this port keeps @undefined@ ('VNoval') and JSON
-- @null@ ('VNull') distinct, so it mirrors the canonical logic directly.
--
-- The canonical algorithm mutates nodes in place and relies on
-- reference-stable nodes (shared references observed by 'walk', 'merge' and
-- 'inject'). Haskell has no mutable native collection, so a node carries an
-- 'Data.IORef.IORef' to its contents — lists are @'IORef' ['Value']@, maps an
-- @'IORef'@ of ordered key\/value pairs, the analog of OCaml's @ref@ or Rust's
-- @Rc\<RefCell\>@. A consequence is that __the whole API runs in 'IO'__: every
-- reader and mutator returns @IO@. Build nodes with 'jm' \/ 'jt', or by running
-- the 'transform' \/ 'inject' engines.
--
-- There are zero third-party runtime dependencies; the regex helper is the
-- in-tree @Vregex@ engine (an RE2 subset).
--
-- == Example
--
-- @
-- import VoxgigStruct
--
-- demo :: IO ()
-- demo = do
--   a <- 'jm' ['VStr' \"a\", 'VNum' 1]; b <- 'jm' ['VStr' \"b\", 'VNum' 2]; xs <- 'jt' [a, b]
--   putStrLn =<< 'stringify' =<< 'merge' xs            -- {a:1,b:2}
-- @
module VoxgigStruct where

import Control.Exception (Exception, throwIO)
import Control.Monad (filterM, foldM, forM_, when)
import Data.Bits (shiftL, (.&.), (.|.))
import Data.Char (toLower, toUpper)
import Data.IORef
import Data.List (findIndex, intercalate, isPrefixOf, sort)
import qualified Data.List as L
import Data.Maybe (fromMaybe)
import Numeric (showHex)
import System.IO.Unsafe (unsafePerformIO)
import Text.Printf (printf)
import Text.Read (readMaybe)
import qualified Vregex

import Prelude hiding (filter)

-- ---------------------------------------------------------------------------
-- Value model
-- ---------------------------------------------------------------------------

-- | The universal JSON-like value: scalars, mutable 'IORef'-backed nodes, functions and sentinels.
data Value
  = VNoval                          -- ^ canonical @undefined@ — property absent
  | VNull                           -- ^ JSON @null@
  | VBool !Bool                     -- ^ boolean
  | VNum !Double                    -- ^ number (integers are whole 'Double's)
  | VStr !String                    -- ^ string
  | VList !(IORef [Value])          -- ^ list \/ array node (mutable, reference-stable)
  | VMap !(IORef [(String, Value)]) -- ^ map \/ object node (ordered, mutable, reference-stable)
  | VFunc Injector                  -- ^ function (a custom injector)
  | VSentinel !String               -- ^ SKIP \/ DELETE marker, compared by tag

-- | A custom @$@-directive handler: injection state, value, key and parent to a result.
type Injector = Inj -> Value -> String -> Value -> IO Value
-- | A post-injection mutation hook (used by validation).
type ModifyFn = Value -> Value -> Value -> Inj -> IO ()

-- | Mutable injection state threaded through the inject\/transform\/validate engines.
data Inj = Inj
  { iMode :: IORef Int              -- ^ current pass (key-pre \/ key-post \/ value)
  , iFull :: IORef Bool             -- ^ whether the string is a whole-value injection
  , iKeyi :: IORef Int              -- ^ index of the current key among its siblings
  , iKeys :: IORef Value            -- ^ the sibling keys being iterated
  , iKey :: IORef Value             -- ^ the current key
  , iIval :: IORef Value            -- ^ the current (injected) value
  , iParent :: IORef Value          -- ^ the parent node of the current value
  , iPath :: IORef Value            -- ^ path from the root to the current value
  , iNodes :: IORef Value           -- ^ ancestor nodes along the current path
  , iHandler :: IORef Injector      -- ^ the active @$@-directive handler
  , iErrs :: IORef Value            -- ^ accumulated validation errors
  , iMeta :: IORef Value            -- ^ caller metadata bag
  , iDparent :: IORef Value         -- ^ parent within the data store
  , iDpath :: IORef Value           -- ^ path within the data store
  , iBase :: IORef Value            -- ^ base name for @$@ lookups
  , iModify :: IORef (Maybe ModifyFn) -- ^ post-injection mutation hook
  , iPrior :: IORef (Maybe Inj)     -- ^ the enclosing injection state, if any
  , iExtra :: IORef Value           -- ^ extra store merged into lookups
  }

-- | The loose @Partial<Injection>@ record the public API accepts.
data InjDef = InjDef
  { dMeta :: Value                  -- ^ caller metadata bag
  , dExtra :: Value                 -- ^ extra store merged into lookups
  , dErrs :: Value                  -- ^ collector for validation errors
  , dModify :: Maybe ModifyFn       -- ^ post-injection mutation hook
  , dHandler :: Maybe Injector      -- ^ custom @$@-directive handler
  , dBase :: Value                  -- ^ base name for @$@ lookups
  , dDparent :: Value               -- ^ parent within the data store
  , dDpath :: Value                 -- ^ path within the data store
  , dKey :: Value                   -- ^ the current key
  }

-- | How callers pass injection state: 'INone', a caller 'InjDef', or a live 'Inj'.
data InjArg = IInj Inj | IDef InjDef | INone

-- | The exception thrown on an unrecoverable structure error.
newtype StructError = StructError String
instance Show StructError where show (StructError m) = m
instance Exception StructError

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

-- | Injection-mode bitmask flags: the key-prefix, key-postfix and value passes.
m_keypre, m_keypost, m_val :: Int
m_keypre = 1
m_keypost = 2
m_val = 4

-- | Dollar-directive name constants (@$KEY@, @$TOP@, @$ERRS@, @$SPEC@ ...) the engines recognise.
s_dkey, s_banno, s_dtop, s_derrs, s_dspec, s_bexact, s_bval, s_bkey, s_bopen :: String
s_dkey = "$KEY"
s_banno = "`$ANNO`"
s_dtop = "$TOP"
s_derrs = "$ERRS"
s_dspec = "$SPEC"
s_bexact = "`$EXACT`"
s_bval = "`$VAL`"
s_bkey = "`$KEY`"
s_bopen = "`$OPEN`"

-- | Single-token syntax constants: empty, backtick, @$@, dot, colon, slash, the literal @"KEY"@ and the @": "@ path separator.
s_mt, s_bt, s_ds, s_dt, s_cn, s_fs, s_key, s_viz :: String
s_mt = ""
s_bt = "`"
s_ds = "$"
s_dt = "."
s_cn = ":"
s_fs = "/"
s_key = "KEY"
s_viz = ": "

-- | Canonical type-name string constants (@"string"@, @"object"@, @"list"@, @"map"@, @"nil"@, @"null"@).
s_string, s_object, s_list, s_map, s_nil, s_null :: String
s_string = "string"
s_object = "object"
s_list = "list"
s_map = "map"
s_nil = "nil"
s_null = "null"

-- | The U+2A2F cross mark used in 'select' error messages.
cross :: String
cross = "\10799"  -- U+2A2F vector cross product (select error messages)

-- | Type-tag bitmask constants (part 1): the wildcard and scalar leaf types.
t_any, t_noval, t_boolean, t_decimal, t_integer, t_number, t_string :: Int
-- | Type-tag bitmask constants (part 2): function, null and the composite @list@/@map@/@node@/@scalar@ groups.
t_function, t_null, t_list, t_map, t_instance, t_scalar, t_node :: Int
t_any = 0x7FFFFFFF
t_noval = 0x40000000
t_boolean = 0x20000000
t_decimal = 0x10000000
t_integer = 0x08000000
t_number = 0x04000000
t_string = 0x02000000
t_function = 0x01000000
t_null = 0x00400000
t_list = 0x00004000
t_map = 0x00002000
t_instance = 0x00001000
t_scalar = 0x00000080
t_node = 0x00000040

-- | Ordered table mapping type-tag indices to their canonical type names.
typenameTbl :: [String]
typenameTbl =
  [ "any", "nil", "boolean", "decimal", "integer", "number", "string", "function"
  , "symbol", "null", "", "", "", "", "", "", "", "list", "map", "instance"
  , "", "", "", "", "scalar", "node" ]

-- | The SKIP and DELETE sentinel values (compared by tag via 'is_skip' \/ 'is_delete').
skip, delete :: Value
skip = VSentinel "skip"
delete = VSentinel "delete"

-- | Maximum recursion depth for 'walk' and the engines (32).
maxdepth :: Int
maxdepth = 32

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

-- | Build a fresh list node from the given elements.
mkList :: [Value] -> IO Value
mkList xs = VList <$> newIORef xs

-- | Build a fresh map node from the given key\/value pairs (insertion order preserved).
mkMap :: [(String, Value)] -> IO Value
mkMap es = VMap <$> newIORef es

-- | A fresh empty list node.
emptyList :: IO Value
emptyList = mkList []

-- | A fresh empty map node.
emptyMap :: IO Value
emptyMap = mkMap []

-- | Wrap an 'Int' as a numeric 'Value'.
vint :: Int -> Value
vint i = VNum (fromIntegral i)

-- | Read the elements of a list node (@[]@ for non-lists).
listItems :: Value -> IO [Value]
listItems (VList r) = readIORef r
listItems _ = return []

-- | Read the key\/value entries of a map node (@[]@ for non-maps).
mapEntries :: Value -> IO [(String, Value)]
mapEntries (VMap m) = readIORef m
mapEntries _ = return []

-- | True for 'VNoval' (canonical @undefined@).
isNoval :: Value -> Bool
isNoval VNoval = True
isNoval _ = False

-- | True for 'VNoval' or 'VNull' — the "no value" test shared by the readers.
isNullish :: Value -> Bool
isNullish VNoval = True
isNullish VNull = True
isNullish _ = False

-- | True for the SKIP sentinel.
is_skip :: Value -> Bool
is_skip (VSentinel "skip") = True
is_skip _ = False

-- | True for the DELETE sentinel.
is_delete :: Value -> Bool
is_delete (VSentinel "delete") = True
is_delete _ = False

-- | True when the value is a string equal to the given text.
vStrEq :: Value -> String -> Bool
vStrEq (VStr s) t = s == t
vStrEq _ _ = False

-- | JavaScript-style truthiness of a value.
vIsTrue :: Value -> Bool
vIsTrue (VBool True) = True
vIsTrue _ = False

-- | True for a string value.
isStr :: Value -> Bool
isStr (VStr _) = True
isStr _ = False

-- | Parse a string as an 'Int', or 'Nothing'.
readIntOpt :: String -> Maybe Int
readIntOpt s = readMaybe (dropPlus s)
  where dropPlus ('+':r) = r
        dropPlus x = x

-- | Return the list with the element at the given index replaced.
setAt :: Int -> a -> [a] -> [a]
setAt i v xs = [if j == i then v else x | (j, x) <- zip [0 ..] xs]

-- | Insert or update a key in an association list, keeping insertion order.
opPut :: String -> Value -> [(String, Value)] -> [(String, Value)]
opPut k v es =
  if any ((== k) . fst) es
    then map (\(k', v') -> if k' == k then (k, v) else (k', v')) es
    else es ++ [(k, v)]

-- | Remove a key from an association list.
opDel :: String -> [(String, Value)] -> [(String, Value)]
opDel k = L.filter ((/= k) . fst)

-- | Monadic 'any': True when the predicate holds for some element.
anyM :: (a -> IO Bool) -> [a] -> IO Bool
anyM _ [] = return False
anyM f (x:xs) = do b <- f x; if b then return True else anyM f xs

-- | Short-circuiting monadic conjunction of a list of @IO Bool@s.
andM :: [IO Bool] -> IO Bool
andM [] = return True
andM (m:ms) = do b <- m; if b then andM ms else return False

-- | True when a 'Double' holds an exact integer value.
isIntegerF :: Double -> Bool
isIntegerF n = not (isNaN n) && not (isInfinite n) && n == fromIntegral (truncate n :: Integer)

-- | Render a 'Double' as JavaScript @String(n)@ does (integral values drop the trailing @.0@).
numToString :: Double -> String
numToString n
  | isNaN n = "NaN"
  | isIntegerF n && abs n < 1e16 = show (truncate n :: Integer)
  | otherwise = shortest 1
  where
    shortest p
      | p > 17 = printf "%.17g" n
      | otherwise =
          let s = printf ("%." ++ show (p :: Int) ++ "g") n :: String
          in if (readMaybe s :: Maybe Double) == Just n then s else shortest (p + 1)

-- | Render @floor n@ as a JavaScript-style number string.
floorNumStr :: Double -> String
floorNumStr n = numToString (fromIntegral (floor n :: Integer))

-- JS `'' + v` / String(v) for keys and concatenation.
-- | JavaScript @String(v)@ for any value (in 'IO' because nodes are read).
jsString :: Value -> IO String
jsString v = case v of
  VNoval -> return "undefined"
  VNull -> return "null"
  VBool b -> return (if b then "true" else "false")
  VNum n -> return (numToString n)
  VStr s -> return s
  VFunc _ -> return "function"
  VSentinel s -> return s
  VMap _ -> return "[object Object]"
  VList r -> do
    elems <- readIORef r
    parts <- mapM (\x -> case x of VNoval -> return ""; VNull -> return ""; _ -> jsString x) elems
    return (intercalate "," parts)

-- pure String(v) for scalar values (the node cases never reach here)
-- | Pure @String(v)@ for scalar values (node cases never reach here).
jsstrPure :: Value -> String
jsstrPure v = case v of
  VNoval -> "undefined"
  VNull -> "null"
  VBool b -> if b then "true" else "false"
  VNum n -> numToString n
  VStr s -> s
  VFunc _ -> "function"
  VSentinel s -> s
  _ -> ""

-- | True when a string is a valid non-negative integer list index.
isIntKey :: String -> Bool
isIntKey s = not (null s) && all (\c -> (c >= '0' && c <= '9') || c == '-') s

-- | Count leading zero bits of a 32-bit word (JavaScript @Math.clz32@).
clz32 :: Int -> Int
clz32 n0 =
  let n = n0 .&. 0xFFFFFFFF
  in if n == 0 then 32 else go n 0
  where
    go n r = if (n .&. 0x80000000) /= 0 then r else go ((n `shiftL` 1) .&. 0xFFFFFFFF) (r + 1)

-- | Split a string on a delimiter character.
splitOn :: Char -> String -> [String]
splitOn c s = case break (== c) s of
  (a, []) -> [a]
  (a, _:rest) -> a : splitOn c rest

-- | True when the first string is a prefix of the second.
isPrefixOf' :: String -> String -> Bool
isPrefixOf' = isPrefixOf

-- | Replace every occurrence of a substring within a string.
replaceAll :: String -> String -> String -> String
replaceAll s find_ repl
  | null find_ = s
  | otherwise = go s
  where
    flen = length find_
    go [] = []
    go str@(c:rest) =
      if find_ `isPrefixOf` str then repl ++ go (drop flen str) else c : go rest

-- ---------------------------------------------------------------------------
-- Minor utilities
-- ---------------------------------------------------------------------------

-- | True when the value is a node (map or list).
isnode :: Value -> Bool
isnode (VMap _) = True
isnode (VList _) = True
isnode _ = False

-- | True when the value is a map node.
ismap :: Value -> Bool
ismap (VMap _) = True
ismap _ = False

-- | True when the value is a list node.
islist :: Value -> Bool
islist (VList _) = True
islist _ = False

-- | True when the value is a function ('VFunc').
isfunc :: Value -> Bool
isfunc (VFunc _) = True
isfunc _ = False

-- | True when the value can serve as a key (non-empty string or a number).
iskey :: Value -> Bool
iskey (VStr s) = s /= ""
iskey (VNum _) = True
iskey _ = False

-- | True for empty\/absent values: noval, null, empty string, or an empty node.
isempty :: Value -> IO Bool
isempty v = case v of
  VNoval -> return True
  VNull -> return True
  VStr s -> return (s == "")
  VList r -> null <$> readIORef r
  VMap m -> null <$> readIORef m
  _ -> return False

-- | Return the first value unless it is nullish, otherwise the default.
getdef :: Value -> Value -> Value
getdef v alt = if isNoval v then alt else v

-- | The canonical integer type tag of a value.
typify :: Value -> Int
typify v = case v of
  VNoval -> t_noval
  VNull -> t_scalar .|. t_null
  VBool _ -> t_scalar .|. t_boolean
  VNum n -> if isNaN n then t_noval
            else if isIntegerF n then t_scalar .|. t_number .|. t_integer
            else t_scalar .|. t_number .|. t_decimal
  VStr _ -> t_scalar .|. t_string
  VFunc _ -> t_scalar .|. t_function
  VList _ -> t_node .|. t_list
  VMap _ -> t_node .|. t_map
  VSentinel _ -> t_node .|. t_map

-- | The canonical type name for a type-tag index.
typename :: Int -> String
typename t =
  let i = clz32 t
  in if i >= 0 && i < length typenameTbl then typenameTbl !! i else head typenameTbl

-- | Number of entries in a node (0 for non-nodes).
size :: Value -> IO Int
size v = case v of
  VList r -> length <$> readIORef r
  VMap m -> length <$> readIORef m
  VStr s -> return (length s)
  VBool b -> return (if b then 1 else 0)
  VNum n -> return (floor n)
  _ -> return 0

-- | Coerce a value to its string-key form.
strkey :: Value -> String
strkey key = case key of
  VNoval -> s_mt
  VStr s -> s
  VBool _ -> s_mt
  VNum n -> if isIntegerF n then numToString n else floorNumStr n
  _ -> s_mt

-- | Sorted map keys, or list indices as strings; @[]@ for non-nodes.
keysof :: Value -> IO [String]
keysof v = case v of
  VMap m -> sort . map fst <$> readIORef m
  VList r -> do elems <- readIORef r; return [show i | i <- [0 .. length elems - 1]]
  _ -> return []

-- | Read a list element by numeric\/string key ('VNoval' when out of range).
listIndex :: IORef [Value] -> Value -> IO Value
listIndex r key = do
  let ks = case key of VStr s -> s; VNum n -> numToString n; _ -> ""
  elems <- readIORef r
  case readIntOpt ks of
    Just i | i >= 0 && i < length elems -> return (elems !! i)
    _ -> return VNoval

-- | Read a node property by key, returning the alt value when absent.
getpropAlt :: Value -> Value -> Value -> IO Value
getpropAlt alt v key
  | isNoval v || isNoval key = return alt
  | otherwise = do
      out <- case v of
        VMap m -> do k <- jsString key; fromMaybe VNoval . lookup k <$> readIORef m
        VList r -> listIndex r key
        _ -> return VNoval
      return (if isNullish out then alt else out)

-- | Read a node property by key ('VNoval' when absent).
getprop :: Value -> Value -> IO Value
getprop = getpropAlt VNoval

-- | Internal raw property reader that preserves 'VNull' literally.
lookup_ :: Value -> Value -> IO Value
lookup_ v key
  | isNoval v || isNoval key = return VNoval
  | otherwise = case v of
      VMap m -> do k <- jsString key; fromMaybe VNoval . lookup k <$> readIORef m
      VList r -> listIndex r key
      _ -> return VNoval

-- | True when a node has a (non-nullish) value at the given key.
haskey :: Value -> Value -> IO Bool
haskey v key = (not . isNullish) <$> getprop v key

-- | Read a list element by key, returning the alt value when absent.
getelemAlt :: Value -> Value -> Value -> IO Value
getelemAlt alt v key
  | isNoval v || isNoval key = return alt
  | otherwise = do
      out <- case v of
        VList r -> do
          let ks = case key of VStr s -> s; VNum n -> numToString n; _ -> ""
          if isIntKey ks
            then do
              elems <- readIORef r
              let len = length elems
              case readIntOpt ks of
                Just nk0 -> let nk = if nk0 < 0 then len + nk0 else nk0
                            in return (if nk >= 0 && nk < len then elems !! nk else VNoval)
                Nothing -> return VNoval
            else return VNoval
        _ -> return VNoval
      if isNullish out
        then case alt of VFunc f -> f dummyInj VNoval "" VNoval; _ -> return alt
        else return out

-- | Read a list element by key ('VNoval' when absent).
getelem :: Value -> Value -> IO Value
getelem = getelemAlt VNoval

-- | Internal string-keyed property reader.
getpropRaw :: Value -> String -> IO Value
getpropRaw v k = case v of
  VMap m -> fromMaybe VNoval . lookup k <$> readIORef m
  VList r -> do
    elems <- readIORef r
    case readIntOpt k of
      Just i | i >= 0 && i < length elems -> return (elems !! i)
      _ -> return VNoval
  _ -> return VNoval

-- | Node entries as @(key, value)@ pairs — map entries or indexed list elements.
itemsPairs :: Value -> IO [(String, Value)]
itemsPairs v =
  if not (isnode v) then return []
  else do ks <- keysof v; mapM (\k -> (,) k <$> getpropRaw v k) ks

-- | Node entries as a list node of @[key, value]@ pairs.
items :: Value -> IO Value
items v = do
  ps <- itemsPairs v
  xs <- mapM (\(k, x) -> mkList [VStr k, x]) ps
  mkList xs

-- | Map each node entry through a function, collecting the results into a list node.
itemsV :: Value -> ((String, Value) -> Value) -> IO Value
itemsV v f = do ps <- itemsPairs v; mkList (map f ps)

-- | Flatten nested lists up to the given depth.
flatten :: Int -> Value -> IO Value
flatten depth l =
  if not (islist l) then return l
  else do
    its <- listItems l
    out <- foldM go [] its
    mkList out
  where
    go acc item =
      if islist item && depth > 0
        then do f <- flatten (depth - 1) item; fis <- listItems f; return (acc ++ fis)
        else return (acc ++ [item])

-- | Keep the node entries satisfying the predicate (shadows 'Prelude.filter').
filter :: Value -> ((String, Value) -> Bool) -> IO Value
filter v check = do
  ps <- itemsPairs v
  mkList [x | (k, x) <- ps, check (k, x)]

-- | Set, or (with a nullish value) delete, a node property; returns the node.
setprop :: Value -> Value -> Value -> IO Value
setprop parent key v
  | not (iskey key) = return parent
  | otherwise = do
      case parent of
        VMap m -> do k <- jsString key; modifyIORef' m (opPut k v)
        VList r -> do
          let ks = case key of VStr s -> s; VNum n -> floorNumStr n; _ -> ""
          case readIntOpt ks of
            Nothing -> return ()
            Just ki -> do
              its <- readIORef r
              let len = length its
              if ki >= 0
                then let ki' = if ki > len then len else ki
                     in if ki' >= len then writeIORef r (its ++ [v]) else writeIORef r (setAt ki' v its)
                else writeIORef r (v : its)
        _ -> return ()
      return parent

-- | Delete a node property; returns the node.
delprop :: Value -> Value -> IO Value
delprop parent key
  | not (iskey key) = return parent
  | otherwise = do
      case parent of
        VMap m -> do k <- jsString key; modifyIORef' m (opDel k)
        VList r -> do
          let ks = case key of VStr s -> s; VNum n -> floorNumStr n; _ -> ""
          case readIntOpt ks of
            Just ki | ki >= 0 -> do
              its <- readIORef r
              when (ki < length its) $ writeIORef r [x | (j, x) <- zip [0 ..] its, j /= ki]
            _ -> return ()
        _ -> return ()
      return parent

-- | Deep copy a value into fresh, independent nodes.
clone :: Value -> IO Value
clone v = case v of
  VList r -> do its <- readIORef r; xs <- mapM clone its; mkList xs
  VMap m -> do es <- readIORef m; es' <- mapM (\(k, x) -> (,) k <$> clone x) es; mkMap es'
  _ -> return v

-- | Sub-list\/substring by start\/end with an inclusive-end flag.
sliceM :: Value -> Value -> Value -> Bool -> IO Value
sliceM v start stop mutate = case v of
  VNum n -> do
    let lo = case start of VNum s -> s; _ -> -(1 / 0)
        hi = case stop of VNum e -> e - 1; _ -> 1 / 0
    return (VNum (max lo (min n hi)))
  _ | islist v || isStr v -> do
        vlen <- size v
        let start' = case (start, stop) of (VNoval, x) | not (isNoval x) -> VNum 0; _ -> start
        case start' of
          VNum sf -> do
            let s0 = truncate sf :: Int
                (s1, e1) =
                  if s0 < 0 then (0, let e = vlen + s0 in if e < 0 then 0 else e)
                  else case stop of
                    VNum ef -> let e = truncate ef :: Int
                               in if e < 0 then (s0, let e2 = vlen + e in if e2 < 0 then 0 else e2)
                                  else if vlen < e then (s0, vlen) else (s0, e)
                    _ -> (s0, vlen)
                s2 = if vlen < s1 then vlen else s1
            if s2 > -1 && s2 <= e1 && e1 <= vlen
              then case v of
                VList r -> do its <- readIORef r
                              let sub = take (e1 - s2) (drop s2 its)
                              if mutate then writeIORef r sub >> return v else mkList sub
                VStr str -> return (VStr (take (e1 - s2) (drop s2 str)))
                _ -> return v
              else case v of
                VList r -> if mutate then writeIORef r [] >> return v else emptyList
                VStr _ -> return (VStr "")
                _ -> return v
          _ -> return v
  _ -> return v

-- | Sub-list\/substring over the half-open range @[start, end)@.
slice :: Value -> Value -> Value -> IO Value
slice v start stop = sliceM v start stop False

-- ----- regex helpers (uniform re_* API + in-tree Vregex) -----

-- | Coerce a value to the source text of a regular expression.
reStr :: Value -> IO String
reStr p = case p of VStr s -> return s; _ -> jsString p

-- | Compile a pattern value into a regex value.
re_compile :: Value -> IO Value
re_compile p = case p of VStr _ -> return p; _ -> VStr <$> jsString p

-- | True when the regex matches the subject.
re_test :: Value -> Value -> IO Value
re_test p input = do ps <- reStr p; is <- reStr input; return (VBool (Vregex.testStr ps is))

-- | First match of the regex in the subject.
re_find :: Value -> Value -> IO Value
re_find p input = do
  ps <- reStr p
  is <- reStr input
  case Vregex.findBounds (Vregex.compile ps) is of
    Just (s, e) -> mkList [VStr (take (e - s) (drop s is))]
    Nothing -> return VNull

-- | All matches of the regex in the subject.
re_find_all :: Value -> Value -> IO Value
re_find_all _ _ = emptyList

-- | Replace regex matches within the subject.
re_replace :: Value -> Value -> Value -> IO Value
re_replace _ input _ = return input

-- | Escape a value for literal use in a regex.
re_escape :: Value -> IO Value
re_escape = escre

-- | Escape a string for literal use in a regular expression.
escre :: Value -> IO Value
escre s = do
  str <- case s of VStr x -> return x; VNoval -> return s_mt; _ -> jsString s
  return $ VStr $ concatMap (\c -> if c `elem` ".*+?^${}()|[]\\" then ['\\', c] else [c]) str

-- | Percent-encode a string for use in a URL.
escurl :: Value -> IO Value
escurl s = do
  str <- case s of VStr x -> return x; VNoval -> return s_mt; _ -> jsString s
  return $ VStr $ concatMap enc str
  where
    enc c = if unreserved c then [c] else '%' : (printf "%02X" (fromEnum c) :: String)
    unreserved c = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
                || (c >= '0' && c <= '9') || c `elem` "-_.!~*'()"

-- ----- json_encode / stringify / jsonify / pad / join / pathify -----

-- | Format an 'Int' as a zero-padded four-digit hex string.
pad4hex :: Int -> String
pad4hex n = let h = showHex n "" in replicate (4 - length h) '0' ++ h

-- | Core JSON encoder (sort-keys and optional indent) shared by 'stringify' \/ 'jsonify'.
jsonEncode :: Bool -> Maybe Int -> Value -> IO String
jsonEncode srt indent = \v -> enc v 0
  where
    esc s = '"' : concatMap escc s ++ "\""
    escc c = case c of
      '"' -> "\\\""
      '\\' -> "\\\\"
      '\n' -> "\\n"
      '\r' -> "\\r"
      '\t' -> "\\t"
      _ | fromEnum c < 32 -> "\\u" ++ pad4hex (fromEnum c)
        | otherwise -> [c]
    enc val level = case val of
      VNoval -> return "null"
      VNull -> return "null"
      VBool b -> return (if b then "true" else "false")
      VNum n -> return (numToString n)
      VStr s -> return (esc s)
      VFunc _ -> return "null"
      VSentinel _ -> return "null"
      VList r -> do
        its <- readIORef r
        if null its then return "[]" else case indent of
          Just ind -> do
            let padStr = replicate (ind * (level + 1)) ' '
                cpad = replicate (ind * level) ' '
            parts <- mapM (\x -> (padStr ++) <$> enc x (level + 1)) its
            return ("[\n" ++ intercalate ",\n" parts ++ "\n" ++ cpad ++ "]")
          Nothing -> do
            parts <- mapM (\x -> enc x (level + 1)) its
            return ("[" ++ intercalate "," parts ++ "]")
      VMap m -> do
        es <- readIORef m
        let ks0 = map fst es
            ks = if srt then sort ks0 else ks0
        if null ks then return "{}" else case indent of
          Just ind -> do
            let padStr = replicate (ind * (level + 1)) ' '
                cpad = replicate (ind * level) ' '
            parts <- mapM (\k -> do x <- maybe (return VNoval) return (lookup k es)
                                    xs <- enc x (level + 1)
                                    return (padStr ++ esc k ++ ": " ++ xs)) ks
            return ("{\n" ++ intercalate ",\n" parts ++ "\n" ++ cpad ++ "}")
          Nothing -> do
            parts <- mapM (\k -> do x <- maybe (return VNoval) return (lookup k es)
                                    xs <- enc x (level + 1)
                                    return (esc k ++ ":" ++ xs)) ks
            return ("{" ++ intercalate "," parts ++ "}")

-- | True when the value graph contains a reference cycle.
hasCycle :: Value -> IO Bool
hasCycle v0 = do
  seen <- newIORef []
  let sameNode (VList a) (VList b) = a == b
      sameNode (VMap a) (VMap b) = a == b
      sameNode _ _ = False
      go v = case v of
        VList r -> do
          s <- readIORef seen
          if any (sameNode v) s then return True
          else do modifyIORef' seen (v :); xs <- readIORef r; anyM go xs
        VMap m -> do
          s <- readIORef seen
          if any (sameNode v) s then return True
          else do modifyIORef' seen (v :); es <- readIORef m; anyM (go . snd) es
        _ -> return False
  go v0

-- | Wrap a string in an ANSI 256-colour escape for pretty output.
prettyColor :: String -> String
prettyColor valstr =
  let colors = [81, 118, 213, 39, 208, 201, 45, 190, 129, 51, 160, 121, 226, 33, 207, 69]
      c = map (\n -> "\ESC[38;5;" ++ show (n :: Int) ++ "m") colors
      clen = length c
      r = "\ESC[0m"
      step (d, o, t) ch
        | ch == '{' || ch == '[' = let d2 = d + 1; o2 = c !! (d2 `mod` clen) in (d2, o2, t ++ o2 ++ [ch])
        | ch == '}' || ch == ']' = let t2 = t ++ o ++ [ch]; d2 = d - 1; o2 = c !! (((d2 `mod` clen) + clen) `mod` clen) in (d2, o2, t2)
        | otherwise = (d, o, t ++ o ++ [ch])
      (_, _, res) = foldl step (0 :: Int, head c, head c) valstr
  in res ++ r

-- | Compact JSON-ish rendering with sort and max-length options.
stringifyFull :: Value -> Value -> Bool -> IO String
stringifyFull v maxlen pretty = case v of
  VNoval -> return (if pretty then "<>" else s_mt)
  _ -> do
    valstr <- case v of
      VStr s -> return s
      _ -> do
        cyc <- hasCycle v
        if cyc then return "__STRINGIFY_FAILED__"
        else do s <- jsonEncode True Nothing v; return (L.filter (/= '"') s)
    let valstr2 = case maxlen of
          VNum m | m > -1 -> let mi = truncate m; l = length valstr
                             in if mi < l then take (max 0 (mi - 3)) valstr ++ "..." else valstr
          _ -> valstr
    if pretty then return (prettyColor valstr2) else return valstr2

-- | Compact, human-readable JSON-ish rendering of a value.
stringify :: Value -> IO String
stringify v = stringifyFull v VNoval False

-- | 'stringify' truncated to a maximum length.
stringifyMax :: Value -> Value -> IO String
stringifyMax v maxlen = stringifyFull v maxlen False

-- | Pretty, indented JSON rendering of a value.
jsonify :: Value -> Value -> IO String
jsonify v flags = case v of
  VNoval -> return s_null
  _ -> do
    indentV <- getpropAlt (VNum 2) flags (VStr "indent")
    let indent = case indentV of VNum n -> truncate n; _ -> 2
    str <- if indent > 0 then jsonEncode False (Just indent) v else jsonEncode False Nothing v
    offV <- getpropAlt (VNum 0) flags (VStr "offset")
    let off = case offV of VNum n -> truncate n; _ -> 0
    if off > 0
      then case lines str of
        (_:rest) -> return ("{\n" ++ intercalate "\n" (map (\l -> replicate off ' ' ++ l) rest))
        [] -> return str
      else return str

-- | Pad a value's string form to a width with a fill character.
pad :: Value -> Value -> Value -> IO String
pad s padding padchar = do
  str <- case s of VStr x -> return x; VNull -> return "null"; _ -> stringify s
  let p = case padding of VNum n -> truncate n; _ -> 44
      pc = case padchar of VStr x -> take 1 (x ++ " "); _ -> " "
  return $ if p > -1
    then let n = p - length str in if n > 0 then str ++ concat (replicate n pc) else str
    else let n = (-p) - length str in if n > 0 then concat (replicate n pc) ++ str else str

-- | Join a list's elements into a string with a separator.
join :: Value -> Value -> Bool -> IO String
join arr sep url =
  if not (islist arr) then return s_mt
  else do
    sepdef <- case sep of VNoval -> return ","; VNull -> return ","; VStr s -> return s; _ -> jsString sep
    let single = length sepdef == 1
        sc = if single then head sepdef else ' '
        stripTrailing = reverse . dropWhile (== sc) . reverse
        stripLeading = dropWhile (== sc)
        collapse str = build 0 str
          where
            nn = length str
            build i s = case s of
              [] -> []
              (ch:_) | ch == sc ->
                let run = takeWhile (== sc) s
                    j = i + length run
                    rest = drop (length run) s
                in if i > 0 && j < nn then sc : build j rest else run ++ build j rest
              _ -> let (seg, rest) = break (== sc) s in seg ++ build (i + length seg) rest
    its <- listItems arr
    let sarr = length its
        process idx s0v = case s0v of
          VStr s | s /= s_mt ->
            let s1 = if single
                       then if url && idx == 0 then stripTrailing s
                            else let a = if idx > 0 then stripLeading s else s
                                     b = if idx < sarr - 1 || not url then stripTrailing a else a
                                 in collapse b
                       else s
            in if s1 /= s_mt then [s1] else []
          _ -> []
        out = concat [process idx s0v | (idx, s0v) <- zip [0 ..] its]
    return (intercalate sepdef out)

-- | Join path parts into a normalised URL.
joinurl :: Value -> IO String
joinurl arr = join arr (VStr "/") True

-- | Substring\/regex replacement over a value's string form.
replace :: Value -> Value -> Value -> IO String
replace s from_ to_ = do
  let ts = typify s
  rs <- if (t_string .&. ts) == 0 then stringify s
        else if ((t_noval .|. t_null) .&. ts) > 0 then return s_mt
        else stringify s
  to_s <- case to_ of VStr x -> return x; _ -> jsString to_
  case from_ of
    VStr f | f /= "" -> return (replaceAll rs f to_s)
    _ -> return rs

-- | Render a path value as a dotted string, with an absent-path marker option.
pathifyFull :: Value -> Value -> Value -> Bool -> IO String
pathifyFull v startin endin absent = do
  mpath <- if islist v then Just <$> listItems v
           else return (if iskey v then Just [v] else Nothing)
  let start = case startin of VNum n -> if n > -1 then truncate n else 0; _ -> 0
      endn = case endin of VNum n -> if n > -1 then truncate n else 0; _ -> 0
  pstr <- case mpath of
    Just p | start >= 0 -> do
      let len = length p
          e = max 0 (len - endn)
          s = min start len
          sub = if s <= e then take (e - s) (drop s p) else []
      if null sub then return (Just "<root>")
      else do
        let fp = L.filter iskey sub
            mapped = map (\pp -> case pp of
                       VNum n -> floorNumStr n
                       VStr x -> L.filter (/= '.') x
                       _ -> "") fp
        return (Just (intercalate "." mapped))
    _ -> return Nothing
  case pstr of
    Just s -> return s
    Nothing -> do
      tl <- if absent then return s_mt else do st <- stringifyMax v (VNum 47); return (s_cn ++ st)
      return ("<unknown-path" ++ tl ++ ">")

-- | Render a path value as a human-readable dotted string.
pathify :: Value -> IO String
pathify v = pathifyFull v VNoval VNoval False

-- ---------------------------------------------------------------------------
-- walk / merge
-- ---------------------------------------------------------------------------

-- | A 'walk' callback: key, value, parent and path to a replacement value.
type WalkFn = Value -> Value -> Value -> Value -> IO Value

-- | Depth-first walk applying optional before\/after transforms at each node.
walk :: Maybe WalkFn -> Maybe WalkFn -> Value -> Value -> IO Value
walk before after md v = walkImpl before after md VNoval VNoval Nothing v

-- | Recursive worker behind 'walk' (carries parent, path and depth).
walkImpl :: Maybe WalkFn -> Maybe WalkFn -> Value -> Value -> Value -> Maybe Value -> Value -> IO Value
walkImpl before after md key parent mpath v = do
  path <- maybe emptyList return mpath
  depth <- size path
  out0 <- case before of Nothing -> return v; Just f -> f key v parent path
  let mdv = case md of VNum n -> if n >= 0 then truncate n else maxdepth; _ -> maxdepth
  if mdv == 0 || (mdv > 0 && mdv <= depth)
    then return out0
    else do
      when (isnode out0) $ do
        prefix <- listItems path
        ps <- itemsPairs out0
        forM_ ps $ \(ckey, child) -> do
          childpath <- mkList (prefix ++ [VStr ckey])
          result <- walkImpl before after (VNum (fromIntegral mdv)) (VStr ckey) out0 (Just childpath) child
          case out0 of
            VMap m -> modifyIORef' m (opPut ckey result)
            VList r -> modifyIORef' r (\xs -> [if i == (read ckey :: Int) then result else x | (i, x) <- zip [0 :: Int ..] xs])
            _ -> return ()
      case after of Nothing -> return out0; Just f -> f key out0 parent path

-- | Deep-merge the source node into the destination in place.
mergeD :: Value -> Value -> IO Value
mergeD objs maxd = do
  let md = case maxd of VNum n -> if n < 0 then 0 else truncate n; _ -> 32
  if not (islist objs) then return objs
  else do
    l <- listItems objs
    let lenlist = length l
    if lenlist == 0 then return VNoval
    else if lenlist == 1 then return (head l)
    else do
      out0 <- do em <- emptyMap; getpropAlt em objs (VNum 0)
      outRef <- newIORef out0
      forM_ [1 .. lenlist - 1] $ \oi -> do
        let obj = l !! oi
        if not (isnode obj) then writeIORef outRef obj
        else do
          o <- readIORef outRef
          cur <- newIORef [o]
          dst <- newIORef [o]
          let grow ref nn = do a <- readIORef ref; when (length a <= nn) (writeIORef ref (a ++ replicate (nn + 1 - length a) VNoval))
              before key vv _parent path = do
                pii <- size path
                if md <= pii then do
                  grow cur pii
                  modifyIORef' cur (setAt pii vv)
                  when (pii > 0) $ do c <- readIORef cur; _ <- setprop (c !! (pii - 1)) key vv; return ()
                  return VNoval
                else if not (isnode vv) then do
                  grow cur pii; modifyIORef' cur (setAt pii vv); return vv
                else do
                  grow dst pii; grow cur pii
                  dpi <- if pii > 0 then do d <- readIORef dst; getprop (d !! (pii - 1)) key
                                    else do d <- readIORef dst; return (d !! pii)
                  modifyIORef' dst (setAt pii dpi)
                  let tval = dpi
                  if isNullish tval then do
                    nn <- if islist vv then emptyList else emptyMap
                    modifyIORef' cur (setAt pii nn); return vv
                  else if (islist vv && islist tval) || (ismap vv && ismap tval) then do
                    modifyIORef' cur (setAt pii tval); return vv
                  else do
                    modifyIORef' cur (setAt pii vv); return VNoval
              after key vv _parent path = do
                ci <- size path
                if ci < 1 then do c <- readIORef cur; return (if not (null c) then head c else vv)
                else do
                  c <- readIORef cur
                  let target = if ci - 1 < length c then c !! (ci - 1) else VNoval
                      value = if ci < length c then c !! ci else VNoval
                  _ <- setprop target key value
                  return value
          res <- walk (Just before) (Just after) VNoval obj
          writeIORef outRef res
      when (md == 0) $ do
        o <- getprop objs (VNum (fromIntegral (lenlist - 1)))
        nn <- if islist o then emptyList else if ismap o then emptyMap else return o
        writeIORef outRef nn
      readIORef outRef

-- | Deep-merge a list of nodes left-to-right (later values win); returns the merged node.
merge :: Value -> IO Value
merge objs = mergeD objs VNoval

-- ---------------------------------------------------------------------------
-- getpath / setpath
-- ---------------------------------------------------------------------------

-- | Accessors reading the @base@\/@dparent@\/@meta@\/@key@\/@dpath@ fields out of an 'InjArg'.
iaBase, iaDparent, iaMeta, iaKey, iaDpath :: InjArg -> IO Value
iaBase ia = case ia of IInj i -> readIORef (iBase i); IDef d -> return (dBase d); INone -> return VNoval
iaDparent ia = case ia of IInj i -> readIORef (iDparent i); IDef d -> return (dDparent d); INone -> return VNoval
iaMeta ia = case ia of IInj i -> readIORef (iMeta i); IDef d -> return (dMeta d); INone -> return VNoval
iaKey ia = case ia of IInj i -> readIORef (iKey i); IDef d -> return (dKey d); INone -> return VNoval
iaDpath ia = case ia of IInj i -> readIORef (iDpath i); IDef d -> return (dDpath d); INone -> return VNoval

-- | The custom injector handler carried by an 'InjArg', if any.
iaHandler :: InjArg -> IO (Maybe Injector)
iaHandler ia = case ia of IInj i -> Just <$> readIORef (iHandler i); IDef d -> return (dHandler d); INone -> return Nothing

-- | True unless the 'InjArg' is 'INone'.
iaIsSome :: InjArg -> Bool
iaIsSome INone = False
iaIsSome _ = True

-- | Split a @meta$...@ style string into its @(prefix, name, suffix)@ parts.
metaPathMatch :: String -> Maybe (String, String, String)
metaPathMatch s = case break (== '$') s of
  (pre, '$':rest) | not (null pre) ->
     case rest of
       (op:after) | (op == '=' || op == '~') && not (null after) -> Just (pre, [op], after)
       _ -> Nothing
  _ -> Nothing

-- | Resolve a dotted\/list path against a store; the by-example @\`$...\`@ path reader.
getpath :: InjArg -> Value -> Value -> IO Value
getpath inj store path = do
  mpa <- case path of
    VList r -> Just <$> readIORef r
    VStr s -> return (Just (map VStr (splitOn '.' s)))
    VNum n -> return (Just [VStr (strkey (VNum n))])
    _ -> return Nothing
  case mpa of
    Nothing -> return VNoval
    Just pa0 -> do
      base <- iaBase inj
      dparent <- iaDparent inj
      injMeta <- iaMeta inj
      injKey <- iaKey inj
      dpath <- iaDpath inj
      src <- if iskey base then getpropAlt store store base else return store
      let numparts = length pa0
      paRef <- newIORef pa0
      vRef <- newIORef store
      let arrGet i = do pa <- readIORef paRef; return (if i >= 0 && i < length pa then pa !! i else VNoval)
      p0init <- arrGet 0
      if isNoval path || isNoval store || (numparts == 1 && vStrEq p0init s_mt) || numparts == 0
        then writeIORef vRef src
        else do
          when (numparts == 1) $ do p0 <- arrGet 0; gv <- getprop store p0; writeIORef vRef gv
          vcur <- readIORef vRef
          if isfunc vcur then return ()
          else do
            writeIORef vRef src
            p0 <- arrGet 0
            case p0 of
              VStr s0 -> case metaPathMatch s0 of
                Just (g1, _, g3) | not (isNoval injMeta) && iaIsSome inj -> do
                  mv <- getprop injMeta (VStr g1); writeIORef vRef mv
                  modifyIORef' paRef (setAt 0 (VStr g3))
                _ -> return ()
              _ -> return ()
            let countAsc p acc = do nxt <- arrGet (p + 1); if vStrEq nxt s_mt then countAsc (p + 1) (acc + 1) else return (acc, p)
                loop pii = do
                  vc <- readIORef vRef
                  if isNoval vc || pii >= numparts then return ()
                  else do
                    raw <- arrGet pii
                    part0 <- case raw of
                      VStr s | iaIsSome inj && s == s_dkey -> return (if not (isNoval injKey) then injKey else raw)
                      VStr s | "$GET:" `isPrefixOf` s -> do sl <- sliceM (VStr s) (VNum 5) (VNum (-1)) False; gp <- getpath INone src sl; VStr <$> stringify gp
                      VStr s | "$REF:" `isPrefixOf` s -> do sl <- sliceM (VStr s) (VNum 5) (VNum (-1)) False; sp <- getprop store (VStr s_dspec); gp <- getpath INone sp sl; VStr <$> stringify gp
                      VStr s | iaIsSome inj && "$META:" `isPrefixOf` s -> do sl <- sliceM (VStr s) (VNum 6) (VNum (-1)) False; gp <- getpath INone injMeta sl; VStr <$> stringify gp
                      _ -> return raw
                    let part = case part0 of VStr s -> VStr (replaceAll s "$$" "$"); _ -> VStr (strkey part0)
                    if vStrEq part s_mt then do
                      (ascends0, pii2) <- countAsc pii 0
                      if iaIsSome inj && ascends0 > 0 then do
                        let ascends = if pii2 == numparts - 1 then ascends0 - 1 else ascends0
                        if ascends == 0 then do writeIORef vRef dparent; loop (pii2 + 1)
                        else do
                          pa2 <- readIORef paRef
                          let tailparts = drop (pii2 + 1) pa2
                          sl <- sliceM dpath (VNum (fromIntegral (negate ascends))) VNoval False
                          tl <- mkList tailparts
                          inner <- mkList [sl, tl]
                          fullpath <- flatten 1 inner
                          dsz <- size dpath
                          if ascends <= dsz then do gp <- getpath INone store fullpath; writeIORef vRef gp
                          else writeIORef vRef VNoval
                      else do writeIORef vRef dparent; loop (pii2 + 1)
                    else do
                      gp <- getprop vc part; writeIORef vRef gp; loop (pii + 1)
            loop 0
      mh <- iaHandler inj
      case mh of
        Just h | iaIsSome inj -> do
          refp <- pathify path
          vc <- readIORef vRef
          case inj of
            IInj i -> do r <- h i vc refp store; writeIORef vRef r
            _ -> do r <- h dummyInj vc refp store; writeIORef vRef r
        _ -> return ()
      readIORef vRef

-- | Set the value at a path within a node, creating intermediate nodes as needed.
setpath :: Value -> Value -> Value -> IO Value
setpath store path v = do
  let ptype = typify path
  parts <- if (t_list .&. ptype) > 0 then (listItems path >>= mkList)
           else if (t_string .&. ptype) > 0 then (case path of VStr s -> mkList (map VStr (splitOn '.' s)); _ -> emptyList)
           else if (t_number .&. ptype) > 0 then mkList [path]
           else return VNoval
  if isNoval parts then return VNoval
  else do
    numparts <- size parts
    parentRef <- newIORef store
    forM_ [0 .. numparts - 2] $ \pii -> do
      parent <- readIORef parentRef
      pkey <- getelem parts (VNum (fromIntegral pii))
      np0 <- getprop parent pkey
      np <- if not (isnode np0) then do
              nextpart <- getelem parts (VNum (fromIntegral (pii + 1)))
              nn <- if (t_number .&. typify nextpart) > 0 then emptyList else emptyMap
              _ <- setprop parent pkey nn; return nn
            else return np0
      writeIORef parentRef np
    parent <- readIORef parentRef
    lastkey <- getelem parts (VNum (-1))
    if is_delete v then delprop parent lastkey >> return parent
    else setprop parent lastkey v >> return parent

-- ---------------------------------------------------------------------------
-- string-pattern helpers (RE2-subset-free)
-- ---------------------------------------------------------------------------

-- | Recognise a whole-string @\`...\`@ injection and return its inner expression.
injectionFull :: String -> Maybe String
injectionFull s =
  let n = length s
  in if n >= 2 && head s == '`' && last s == '`'
     then let inner = take (n - 2) (drop 1 s)
          in if '`' `elem` inner then Nothing
             else if isDollarUpper inner then Just (takeDollarName inner) else Just inner
     else Nothing
  where
    upper c = c >= 'A' && c <= 'Z'
    digit c = c >= '0' && c <= '9'
    lengthLetters str j = if j < length str && upper (str !! j) then lengthLetters str (j + 1) else j
    lettersDigits str k = if k < length str && digit (str !! k) then lettersDigits str (k + 1) else k
    isDollarUpper inner =
      length inner > 1 && head inner == '$' &&
      let le = lengthLetters inner 1
      in le > 1 && lettersDigits inner le == length inner
    takeDollarName inner = take (lengthLetters inner 1) inner

-- | Replace each @\`...\`@ backtick injection inside a string via the given expander.
injectionPartialReplace :: String -> (String -> IO String) -> IO String
injectionPartialReplace s f = go s
  where
    go [] = return []
    go ('`':rest) = case break (== '`') rest of
      (inner, '`':rest2) -> do r <- f inner; rs <- go rest2; return (r ++ rs)
      -- no closing backtick: break's second element is empty here, so emit the
      -- literal '`' and carry on. A catch-all (not `(_, [])`) keeps GHC's
      -- exhaustiveness checker happy since it can't prove the suffix is empty.
      _ -> do rs <- go rest; return ('`' : rs)
    go (c:rest) = (c :) <$> go rest

-- | Rewrite @$NAME@ transform directives to their canonical spellings.
replaceTransformNames :: String -> String
replaceTransformNames = go
  where
    upper c = c >= 'A' && c <= 'Z'
    go [] = []
    go ('`':'$':rest) =
      let (letters, rest2) = span upper rest
      in case rest2 of
           ('`':rest3) | not (null letters) -> map toLower letters ++ go rest3
           _ -> '`' : go ('$':rest)
    go (c:rest) = c : go rest

-- ---------------------------------------------------------------------------
-- Injection state
-- ---------------------------------------------------------------------------

-- | Create a fresh injection state ('Inj') for a value and store.
newInj :: Value -> Value -> IO Inj
newInj v parent = do
  keys <- mkList [VStr s_dtop]
  path <- mkList [VStr s_dtop]
  nodes <- mkList [parent]
  errs <- emptyList
  meta <- emptyMap
  dpath <- mkList [VStr s_dtop]
  Inj <$> newIORef m_val <*> newIORef False <*> newIORef 0
      <*> newIORef keys <*> newIORef (VStr s_dtop) <*> newIORef v
      <*> newIORef parent <*> newIORef path <*> newIORef nodes
      <*> newIORef injectHandler <*> newIORef errs <*> newIORef meta
      <*> newIORef VNoval <*> newIORef dpath <*> newIORef (VStr s_dtop)
      <*> newIORef Nothing <*> newIORef Nothing <*> newIORef VNoval

-- | Recurse the injection engine into a node's children.
injDescend :: Inj -> IO Value
injDescend inj = do
  meta <- readIORef (iMeta inj)
  case meta of
    VMap _ -> do
      d <- getpropRaw meta "__d"
      let dn = case d of VNum n -> n; _ -> 0
      _ <- setprop meta (VStr "__d") (VNum (dn + 1)); return ()
    _ -> return ()
  path <- readIORef (iPath inj)
  parentkey <- getelem path (VNum (-2))
  dparent <- readIORef (iDparent inj)
  if isNoval dparent then do
    dpath <- readIORef (iDpath inj)
    sz <- size dpath
    when (sz > 1) $ do its <- listItems dpath; nl <- mkList (its ++ [parentkey]); writeIORef (iDpath inj) nl
  else when (not (isNoval parentkey)) $ do
    dp <- getprop dparent parentkey; writeIORef (iDparent inj) dp
    dpath <- readIORef (iDpath inj)
    lastpart <- getelem dpath (VNum (-1))
    pk <- jsString parentkey
    if vStrEq lastpart ("$:" ++ pk)
      then do sl <- sliceM dpath (VNum (-1)) VNoval False; writeIORef (iDpath inj) sl
      else do its <- listItems dpath; nl <- mkList (its ++ [parentkey]); writeIORef (iDpath inj) nl
  readIORef (iDparent inj)

-- | Derive the child injection state for one entry of a node.
injChild :: Inj -> Int -> Value -> IO Inj
injChild inj keyi keys = do
  kv <- getelem keys (VNum (fromIntegral keyi))
  let key = strkey kv
  v <- readIORef (iIval inj)
  ival <- getprop v (VStr key)
  ipath <- readIORef (iPath inj); pitems <- listItems ipath; npath <- mkList (pitems ++ [VStr key])
  inodes <- readIORef (iNodes inj); nitems <- listItems inodes; nnodes <- mkList (nitems ++ [v])
  idpath <- readIORef (iDpath inj); ditems <- listItems idpath; ndpath <- mkList ditems
  mode <- readIORef (iMode inj); full <- readIORef (iFull inj); handler <- readIORef (iHandler inj)
  errs <- readIORef (iErrs inj); meta <- readIORef (iMeta inj); base <- readIORef (iBase inj)
  modify <- readIORef (iModify inj); dparent <- readIORef (iDparent inj); extra <- readIORef (iExtra inj)
  Inj <$> newIORef mode <*> newIORef full <*> newIORef keyi
      <*> newIORef keys <*> newIORef (VStr key) <*> newIORef ival
      <*> newIORef v <*> newIORef npath <*> newIORef nnodes
      <*> newIORef handler <*> newIORef errs <*> newIORef meta
      <*> newIORef dparent <*> newIORef ndpath <*> newIORef base
      <*> newIORef modify <*> newIORef (Just inj) <*> newIORef extra

-- | Write a value into an ancestor of the current injection target.
injSetval :: Int -> Inj -> Value -> IO Value
injSetval ancestor inj v = do
  (target, key) <- if ancestor < 2
    then do p <- readIORef (iParent inj); k <- readIORef (iKey inj); return (p, k)
    else do ns <- readIORef (iNodes inj); ps <- readIORef (iPath inj)
            t <- getelem ns (VNum (fromIntegral (negate ancestor)))
            k <- getelem ps (VNum (fromIntegral (negate ancestor)))
            return (t, k)
  if isNoval v then delprop target key else setprop target key v

-- | Write a value into the immediate parent of the injection target.
injSetval1 :: Inj -> Value -> IO Value
injSetval1 = injSetval 1

-- | Placeholder 'Inj' for the two corpus-unreached paths that need one (built with 'unsafePerformIO'; do not rely on its state).
dummyInj :: Inj
dummyInj = unsafePerformIO $ do
  parent <- mkMap [(s_dtop, VNoval)]
  newInj VNoval parent
{-# NOINLINE dummyInj #-}

-- ---------------------------------------------------------------------------
-- inject
-- ---------------------------------------------------------------------------

-- | Run the injection engine: expand @\`...\`@ references in a spec against a store.
inject :: InjArg -> Value -> Value -> IO Value
inject injarg v store = do
  state <- case injarg of
    IInj i -> return i
    _ -> do
      parent <- mkMap [(s_dtop, v)]
      i <- newInj v parent
      writeIORef (iDparent i) store
      el <- emptyList
      errs <- getpropAlt el store (VStr s_derrs)
      writeIORef (iErrs i) errs
      meta <- readIORef (iMeta i)
      case meta of VMap _ -> setprop meta (VStr "__d") (VNum 0) >> return (); _ -> return ()
      case injarg of
        IDef d -> do
          case dModify d of Just _ -> writeIORef (iModify i) (dModify d); Nothing -> return ()
          when (not (isNoval (dExtra d))) $ writeIORef (iExtra i) (dExtra d)
          when (not (isNoval (dMeta d))) $ writeIORef (iMeta i) (dMeta d)
          case dHandler d of Just h -> writeIORef (iHandler i) h; Nothing -> return ()
        _ -> return ()
      return i
  _ <- injDescend state
  v' <- if isnode v then do
          nodekeys0 <- case v of
            VMap m -> do es <- readIORef m
                         let ks = map fst es
                             normal = sort (L.filter (notElem '$') ks)
                             trans = sort (L.filter (elem '$') ks)
                         return (normal ++ trans)
            VList r -> do its <- readIORef r; return [show i | i <- [0 .. length its - 1]]
            _ -> return []
          nkRef <- newIORef nodekeys0
          nkiRef <- newIORef 0
          let loop = do
                nki <- readIORef nkiRef
                nks <- readIORef nkRef
                if nki >= length nks then return ()
                else do
                  keysv <- mkList (map VStr nks)
                  childinj <- injChild state nki keysv
                  nodekeyV <- readIORef (iKey childinj)
                  writeIORef (iMode childinj) m_keypre
                  nkstr <- jsString nodekeyV
                  prekey <- injectstr nkstr store (Just childinj)
                  ck <- readIORef (iKeys childinj); ckl <- listItems ck; ckls <- mapM jsString ckl
                  writeIORef nkRef ckls
                  when (not (isNoval prekey)) $ do
                    iv <- getprop v prekey
                    writeIORef (iIval childinj) iv
                    writeIORef (iMode childinj) m_val
                    _ <- inject (IInj childinj) iv store
                    ck2 <- readIORef (iKeys childinj); ckl2 <- listItems ck2; ckls2 <- mapM jsString ckl2
                    writeIORef nkRef ckls2
                    writeIORef (iMode childinj) m_keypost
                    _ <- injectstr nkstr store (Just childinj)
                    ck3 <- readIORef (iKeys childinj); ckl3 <- listItems ck3; ckls3 <- mapM jsString ckl3
                    writeIORef nkRef ckls3
                  cki <- readIORef (iKeyi childinj)
                  writeIORef nkiRef (cki + 1)
                  loop
          loop
          return v
        else case v of
          VStr _ -> do
            writeIORef (iMode state) m_val
            sv <- jsString v
            nv <- injectstr sv store (Just state)
            when (not (is_skip nv)) $ injSetval1 state nv >> return ()
            return nv
          _ -> return v
  modify <- readIORef (iModify state)
  case modify of
    Just f | not (is_skip v') -> do
      mkey <- readIORef (iKey state); mparent <- readIORef (iParent state); mval <- getprop mparent mkey
      f mval mkey mparent state
    _ -> return ()
  writeIORef (iIval state) v'
  parentS <- readIORef (iParent state)
  lookup_ parentS (VStr s_dtop)

-- | Default injector handler dispatching @$@ directives during injection.
injectHandler :: Injector
injectHandler inj v refstr store = do
  let iscmd = isfunc v && (refstr == "" || s_ds `isPrefixOf` refstr)
  if iscmd then case v of VFunc f -> f inj v refstr store; _ -> return v
  else do
    mode <- readIORef (iMode inj); full <- readIORef (iFull inj)
    if mode == m_val && full then do _ <- injSetval1 inj v; return v else return v

-- | Expand the injections within a single string.
injectstr :: String -> Value -> Maybe Inj -> IO Value
injectstr v store injOpt =
  if v == s_mt then return (VStr s_mt)
  else case injectionFull v of
    Just pathref0 -> do
      case injOpt of Just i -> writeIORef (iFull i) True; Nothing -> return ()
      let pathref = if length pathref0 > 3 then replaceAll (replaceAll pathref0 "$BT" s_bt) "$DS" s_ds else pathref0
          ia = case injOpt of Just i -> IInj i; Nothing -> INone
      getpath ia store (VStr pathref)
    Nothing -> do
      out <- injectionPartialReplace v $ \ref0 -> do
        let refp = if length ref0 > 3 then replaceAll (replaceAll ref0 "$BT" s_bt) "$DS" s_ds else ref0
        case injOpt of Just i -> writeIORef (iFull i) False; Nothing -> return ()
        let ia = case injOpt of Just i -> IInj i; Nothing -> INone
        found <- getpath ia store (VStr refp)
        case found of
          VNoval -> return s_mt
          VStr s -> return (if s == "__NULL__" then "null" else s)
          VFunc _ -> return s_mt
          _ -> jsonEncode False Nothing found
      case injOpt of
        Just i -> do writeIORef (iFull i) True; h <- readIORef (iHandler i); h i (VStr out) v store
        Nothing -> return (VStr out)

-- ---------------------------------------------------------------------------
-- transform commands
-- ---------------------------------------------------------------------------

-- | @$DELETE@ transform: remove the target key.
transformDelete :: Injector
transformDelete inj _ _ _ = do p <- readIORef (iParent inj); k <- readIORef (iKey inj); _ <- delprop p k; return VNoval

-- | @$COPY@ transform: copy the same-named value from the data.
transformCopy :: Injector
transformCopy inj _ _ _ = do
  mode <- readIORef (iMode inj)
  if mode == m_keypre || mode == m_keypost then readIORef (iKey inj)
  else do dp <- readIORef (iDparent inj); k <- readIORef (iKey inj); out <- lookup_ dp k; _ <- injSetval1 inj out; return out

-- | @$KEY@ transform: inject the current key.
transformKey :: Injector
transformKey inj _ _ _ = do
  mode <- readIORef (iMode inj)
  if mode /= m_val then return VNoval
  else do
    p <- readIORef (iParent inj)
    keyspec <- lookup_ p (VStr s_bkey)
    if not (isNoval keyspec) then do _ <- delprop p (VStr s_bkey); dp <- readIORef (iDparent inj); getprop dp keyspec
    else do
      anno <- lookup_ p (VStr s_banno)
      fromanno <- lookup_ anno (VStr s_key)
      if not (isNoval fromanno) then return fromanno
      else do pa <- readIORef (iPath inj); getelem pa (VNum (-2))

-- | @\`$ANNO\`@ annotation transform.
transformAnno :: Injector
transformAnno inj _ _ _ = do p <- readIORef (iParent inj); _ <- delprop p (VStr s_banno); return VNoval

-- | @$MERGE@ transform: merge nodes into the target.
transformMerge :: Injector
transformMerge inj _ _ _ = do
  mode <- readIORef (iMode inj)
  if mode == m_keypre then readIORef (iKey inj)
  else if mode == m_keypost then do
    p <- readIORef (iParent inj); k <- readIORef (iKey inj)
    args0 <- getprop p k
    args <- if islist args0 then return args0 else mkList [args0]
    _ <- injSetval1 inj VNoval
    pc <- clone p
    l1 <- mkList [p]
    l3 <- mkList [pc]
    inner <- mkList [l1, args, l3]
    mergelist <- flatten 1 inner
    _ <- merge mergelist
    readIORef (iKey inj)
  else return VNoval

-- | @$EACH@ transform: expand a template across a collection.
transformEach :: Injector
transformEach inj _ _ store = do
  keys <- readIORef (iKeys inj)
  when (islist keys) $ do _ <- sliceM keys (VNum 0) (VNum 1) True; return ()
  mode <- readIORef (iMode inj)
  if mode /= m_val then return VNoval
  else do
    parent <- readIORef (iParent inj)
    psz <- size parent
    srcpath <- if psz > 1 then getelem parent (VNum 1) else return VNoval
    child_tm <- if psz > 2 then do e <- getelem parent (VNum 2); clone e else return VNoval
    base <- readIORef (iBase inj)
    srcstore <- getpropAlt store store base
    src <- getpath (IInj inj) srcstore srcpath
    path0 <- readIORef (iPath inj)
    tkey <- getelem path0 (VNum (-2))
    nodes <- readIORef (iNodes inj)
    target <- do t <- getelem nodes (VNum (-2)); if isNullish t then getelem nodes (VNum (-1)) else return t
    rvalRef <- newIORef =<< emptyList
    when (isnode src) $ do
      tvall <- case src of
        VList r -> do its <- readIORef r; mapM (\_ -> clone child_tm) its
        VMap m -> do es <- readIORef m
                     mapM (\(k, _) -> do cc <- clone child_tm
                                         when (ismap cc) (do anno <- mkMap [(s_key, VStr k)]; _ <- setprop cc (VStr s_banno) anno; return ())
                                         return cc) es
        _ -> return []
      tvalv <- mkList tvall
      tcurrent <- case src of
        VMap m -> do es <- readIORef m; mkList (map snd es)
        VList r -> do its <- readIORef r; mkList its
        _ -> return src
      when (length tvall > 0) $ do
        path <- readIORef (iPath inj)
        ckey <- getelem path (VNum (-2))
        plist <- listItems path
        tpath <- mkList (if null plist then [] else take (length plist - 1) plist)
        dpathRef <- newIORef [VStr s_dtop]
        case srcpath of
          VStr sp | sp /= s_mt -> forM_ (splitOn '.' sp) (\pp -> when (pp /= s_mt) (modifyIORef' dpathRef (++ [VStr pp])))
          _ -> return ()
        cks <- jsString ckey
        when (not (isNoval ckey)) $ modifyIORef' dpathRef (++ [VStr ("$:" ++ cks)])
        tcur0 <- mkMap [(cks, tcurrent)]
        tcurRef <- newIORef tcur0
        tpsz <- size tpath
        when (tpsz > 1) $ do
          pkey <- getelemAlt (VStr s_dtop) path (VNum (-3))
          pks <- jsString pkey
          modifyIORef' dpathRef (++ [VStr ("$:" ++ pks)])
          tc <- readIORef tcurRef; ntc <- mkMap [(pks, tc)]; writeIORef tcurRef ntc
        ckeyList <- if not (isNoval ckey) then mkList [ckey] else emptyList
        tinj <- injChild inj 0 ckeyList
        writeIORef (iPath tinj) tpath
        nlist <- listItems nodes
        nn <- mkList (if null nlist then [] else take (length nlist - 1) nlist)
        writeIORef (iNodes tinj) nn
        tinjNodes <- readIORef (iNodes tinj); tnsz <- size tinjNodes
        tparent <- if tnsz > 0 then getelem tinjNodes (VNum (-1)) else return VNoval
        writeIORef (iParent tinj) tparent
        when (not (isNoval ckey) && not (isNoval tparent)) $ do _ <- setprop tparent ckey tvalv; return ()
        writeIORef (iIval tinj) tvalv
        dpv <- readIORef dpathRef; dpl <- mkList dpv; writeIORef (iDpath tinj) dpl
        tcur <- readIORef tcurRef; writeIORef (iDparent tinj) tcur
        _ <- inject (IInj tinj) tvalv store
        iv <- readIORef (iIval tinj); writeIORef rvalRef iv
    rval <- readIORef rvalRef
    _ <- setprop target tkey rval
    rsz <- size rval
    if islist rval && rsz > 0 then getelem rval (VNum 0) else return VNoval

-- | @$PACK@ transform: pack a collection into a keyed map.
transformPack :: Injector
transformPack inj _ _ store = do
  mode <- readIORef (iMode inj)
  k0 <- readIORef (iKey inj)
  if mode /= m_keypre || not (isStr k0) then return VNoval
  else do
    parent <- readIORef (iParent inj)
    nodes <- readIORef (iNodes inj)
    key <- readIORef (iKey inj)
    argsVal <- getprop parent key
    asz <- size argsVal
    if not (islist argsVal) || asz < 2 then return VNoval
    else do
      srcpath <- getelem argsVal (VNum 0)
      origchildspec <- getelem argsVal (VNum 1)
      path <- readIORef (iPath inj)
      tkey <- getelem path (VNum (-2))
      pathsize <- size path
      target <- do t <- getelem nodes (VNum (fromIntegral (pathsize - 2))); if isNullish t then getelem nodes (VNum (fromIntegral (pathsize - 1))) else return t
      base <- readIORef (iBase inj)
      srcstore <- getpropAlt store store base
      src0 <- getpath (IInj inj) srcstore srcpath
      src <- if not (islist src0)
               then if ismap src0 then do ps <- itemsPairs src0; xs <- mapM (\(k, node) -> do anno <- mkMap [(s_key, VStr k)]; _ <- setprop node (VStr s_banno) anno; return node) ps; mkList xs
                    else return VNoval
               else return src0
      if isNoval src then return VNoval
      else do
        keypath <- getprop origchildspec (VStr s_bkey)
        childspec <- delprop origchildspec (VStr s_bkey)
        child <- getpropAlt childspec childspec (VStr s_bval)
        tval <- emptyMap
        srcPairs <- itemsPairs src
        forM_ srcPairs $ \(srckey, srcnode) -> do
          k <- if isNoval keypath then return (VStr srckey)
               else case keypath of
                 VStr kp | s_bt `isPrefixOf` kp -> do em <- emptyMap; dt <- mkMap [(s_dtop, srcnode)]; ls <- mkList [em, store, dt]; mst <- mergeD ls (VNum 1); inject INone (VStr kp) mst
                 _ -> getpath (IInj inj) srcnode keypath
          tchild <- clone child
          _ <- setprop tval k tchild
          anno <- getprop srcnode (VStr s_banno)
          if isNoval anno then delprop tchild (VStr s_banno) >> return () else setprop tchild (VStr s_banno) anno >> return ()
        rvalRef <- newIORef =<< emptyMap
        empty <- isempty tval
        when (not empty) $ do
          tsrc <- emptyMap
          srcItems <- listItems src
          forM_ (zip [0 ..] srcItems) $ \(i, node) -> do
            kn <- if isNoval keypath then return (vint i)
                  else case keypath of
                    VStr kp | s_bt `isPrefixOf` kp -> do em <- emptyMap; dt <- mkMap [(s_dtop, node)]; ls <- mkList [em, store, dt]; mst <- mergeD ls (VNum 1); inject INone (VStr kp) mst
                    _ -> getpath (IInj inj) node keypath
            _ <- setprop tsrc kn node; return ()
          tpath <- sliceM path (VNum (-1)) VNoval False
          ckey <- getelem path (VNum (-2))
          dpathRef <- newIORef [VStr s_dtop]
          case srcpath of
            VStr sp -> forM_ (splitOn '.' sp) (\pp -> when (pp /= s_mt) (modifyIORef' dpathRef (++ [VStr pp])))
            _ -> return ()
          cks <- jsString ckey
          modifyIORef' dpathRef (++ [VStr ("$:" ++ cks)])
          tcur0 <- mkMap [(cks, tsrc)]
          tcurRef <- newIORef tcur0
          tpsz <- size tpath
          when (tpsz > 1) $ do
            pkey <- getelemAlt (VStr s_dtop) path (VNum (-3))
            pks <- jsString pkey
            modifyIORef' dpathRef (++ [VStr ("$:" ++ pks)])
            tc <- readIORef tcurRef; ntc <- mkMap [(pks, tc)]; writeIORef tcurRef ntc
          ckl <- mkList [ckey]
          tinj <- injChild inj 0 ckl
          writeIORef (iPath tinj) tpath
          nn <- sliceM nodes (VNum (-1)) VNoval False
          writeIORef (iNodes tinj) nn
          tnodes <- readIORef (iNodes tinj); tparent <- getelem tnodes (VNum (-1))
          writeIORef (iParent tinj) tparent
          writeIORef (iIval tinj) tval
          dpv <- readIORef dpathRef; dpl <- mkList dpv; writeIORef (iDpath tinj) dpl
          tcur <- readIORef tcurRef; writeIORef (iDparent tinj) tcur
          _ <- inject (IInj tinj) tval store
          iv <- readIORef (iIval tinj); writeIORef rvalRef iv
        rval <- readIORef rvalRef
        _ <- setprop target tkey rval
        return VNoval

-- | @$REF@ transform: resolve a reference within the store.
transformRef :: Injector
transformRef inj v _ store = do
  mode <- readIORef (iMode inj)
  if mode /= m_val then return VNoval
  else do
    nodes <- readIORef (iNodes inj)
    parent <- readIORef (iParent inj)
    refpath <- lookup_ parent (VNum 1)
    keys <- readIORef (iKeys inj); ksz <- size keys; writeIORef (iKeyi inj) ksz
    specFunc <- getprop store (VStr s_dspec)
    case specFunc of
      VFunc f -> do
        spec <- f inj VNoval "" VNoval
        refv <- getpath INone spec refpath
        hasSubRef <- newIORef False
        when (isnode refv) $ do _ <- walk (Just (\_ v2 _ _ -> do when (vStrEq v2 "`$REF`") (writeIORef hasSubRef True); return v2)) Nothing VNoval refv; return ()
        tref <- clone refv
        ipath <- readIORef (iPath inj); ipsz <- size ipath
        cpath <- sliceM ipath (VNum 0) (VNum (fromIntegral (ipsz - 3))) False
        tpath <- sliceM ipath (VNum 0) (VNum (fromIntegral (ipsz - 1))) False
        tcur <- getpath INone store cpath
        tval <- getpath INone store tpath
        rvalRef <- newIORef VNoval
        hasSub <- readIORef hasSubRef
        when (not (isNoval refv) && (not hasSub || not (isNoval tval))) $ do
          lastT <- getelem tpath (VNum (-1)); cl <- mkList [lastT]
          cs <- injChild inj 0 cl
          writeIORef (iPath cs) tpath
          inodes <- readIORef (iNodes inj); insz <- size inodes
          nn <- sliceM inodes (VNum 0) (VNum (fromIntegral (insz - 1))) False
          writeIORef (iNodes cs) nn
          parent2 <- getelem nodes (VNum (-2)); writeIORef (iParent cs) parent2
          writeIORef (iIval cs) tref
          writeIORef (iDparent cs) tcur
          _ <- inject (IInj cs) tref store
          iv <- readIORef (iIval cs); writeIORef rvalRef iv
        rval <- readIORef rvalRef
        _ <- injSetval 2 inj rval
        prior <- readIORef (iPrior inj)
        case prior of
          Just p -> when (islist parent) $ do pk <- readIORef (iKeyi p); writeIORef (iKeyi p) (pk - 1)
          Nothing -> return ()
        return v
      _ -> return VNoval

-- ---------------------------------------------------------------------------
-- formatters / transform_format / transform_apply / transform
-- ---------------------------------------------------------------------------

-- | @String(v)@ used by the transform formatters (@null@ prints as @"null"@).
jsstr :: Value -> IO String
jsstr v = case v of
  VNull -> return "null"
  VBool b -> return (if b then "true" else "false")
  _ -> jsString v

-- | Parse a string as a 'Double', defaulting to 0.
readDoubleOr0 :: String -> Double
readDoubleOr0 s = fromMaybe 0 (readMaybe s :: Maybe Double)

-- | A @$FORMAT@ value formatter.
type Formatter = Value -> Value -> IO Value

-- | Table of named @$FORMAT@ value formatters.
formatterTbl :: [(String, Formatter)]
formatterTbl =
  [ ("identity", \_ v -> return v)
  , ("upper", \_ v -> if isnode v then return v else do s <- jsstr v; return (VStr (map toUpper s)))
  , ("lower", \_ v -> if isnode v then return v else do s <- jsstr v; return (VStr (map toLower s)))
  , ("string", \_ v -> if isnode v then return v else do s <- jsstr v; return (VStr s))
  , ("number", \_ v -> if isnode v then return v
                       else do s <- jsstr v; let n = readDoubleOr0 s in return (VNum (if isNaN n then 0 else n)))
  , ("integer", \_ v -> if isnode v then return v
                        else do s <- jsstr v; let n = readDoubleOr0 s in return (VNum (fromIntegral (truncate (if isNaN n then 0 else n) :: Integer))))
  , ("concat", \k v -> if isNoval k && islist v
                       then do iv <- itemsV v (\(_, x) -> if isnode x then VStr s_mt else VStr (jsstrPure x)); s <- join iv (VStr s_mt) False; return (VStr s)
                       else return v)
  ]

-- | Decide whether a directive fires on the current key-pre\/key-post\/value pass.
check_placement :: Int -> String -> Int -> Inj -> IO Bool
check_placement modes ijname parenttypes inj = do
  modenum <- readIORef (iMode inj)
  if (modes .&. modenum) == 0 then do
    let allowed = L.filter (\m -> (modes .&. m) /= 0) [m_keypre, m_keypost, m_val]
        placements = intercalate "," (map (\m -> if m == m_val then "value" else "key") allowed)
        cur = if modenum == m_val then "value" else "key"
    errs <- readIORef (iErrs inj); esz <- size errs
    _ <- setprop errs (VNum (fromIntegral esz)) (VStr ("$" ++ ijname ++ ": invalid placement as " ++ cur ++ ", expected: " ++ placements ++ "."))
    return False
  else do
    ie <- isempty (VNum (fromIntegral parenttypes))
    if not ie then do
      p <- readIORef (iParent inj)
      let ptype = typify p
      if (parenttypes .&. ptype) == 0 then do
        errs <- readIORef (iErrs inj); esz <- size errs
        _ <- setprop errs (VNum (fromIntegral esz)) (VStr ("$" ++ ijname ++ ": invalid placement in parent " ++ typename ptype ++ ", expected: " ++ typename parenttypes ++ "."))
        return False
      else return True
    else return True

-- | Collect the argument values a custom injector declares it needs.
injector_args :: [Int] -> Value -> IO [Value]
injector_args argtypes args = do
  let numargs = length argtypes
  foundRef <- newIORef (replicate (1 + numargs) VNoval)
  let go [] = return ()
      go ((argi, at):rest) = do
        arg <- getelem args (VNum (fromIntegral argi))
        let argtype = typify arg
        if (at .&. argtype) == 0 then do
          s <- stringifyMax arg (VNum 22)
          modifyIORef' foundRef (setAt 0 (VStr ("invalid argument: " ++ s ++ " (" ++ typename argtype ++ " at position " ++ show (1 + argi) ++ ") is not of type: " ++ typename at ++ ".")))
        else do modifyIORef' foundRef (setAt (1 + argi) arg); go rest
  go (zip [0 ..] argtypes)
  readIORef foundRef

-- | Build the child injection state a custom injector operates on.
inject_child :: Value -> Value -> Inj -> IO Inj
inject_child child store inj = do
  prior <- readIORef (iPrior inj)
  cinjRef <- newIORef inj
  case prior of
    Just pr -> do
      pprior <- readIORef (iPrior pr)
      case pprior of
        Just pp -> do
          pkeyi <- readIORef (iKeyi pr); pkeys <- readIORef (iKeys pr)
          c <- injChild pp pkeyi pkeys
          writeIORef (iIval c) child
          cp <- readIORef (iParent c); prk <- readIORef (iKey pr); _ <- setprop cp prk child
          writeIORef cinjRef c
        Nothing -> do
          ikeyi <- readIORef (iKeyi inj); ikeys <- readIORef (iKeys inj)
          c <- injChild pr ikeyi ikeys
          writeIORef (iIval c) child
          cp <- readIORef (iParent c); ik <- readIORef (iKey inj); _ <- setprop cp ik child
          writeIORef cinjRef c
    Nothing -> return ()
  cinj <- readIORef cinjRef
  _ <- inject (IInj cinj) child store
  return cinj

-- | @$FORMAT@ transform: format a value via a named formatter.
transformFormat :: Injector
transformFormat inj _ _ store = do
  keys <- readIORef (iKeys inj); _ <- sliceM keys (VNum 0) (VNum 1) True
  mode <- readIORef (iMode inj)
  if mode /= m_val then return VNoval
  else do
    parent <- readIORef (iParent inj)
    name <- lookup_ parent (VNum 1)
    child <- lookup_ parent (VNum 2)
    path <- readIORef (iPath inj)
    tkey <- getelem path (VNum (-2))
    nodes <- readIORef (iNodes inj)
    target <- do t <- getelem nodes (VNum (-2)); if isNullish t then getelem nodes (VNum (-1)) else return t
    cinj <- inject_child child store inj
    resolved <- readIORef (iIval cinj)
    nameKey <- jsString name
    let formatter = if (t_function .&. typify name) > 0
          then Just (\k vv -> case name of { VFunc f -> do { ks <- jsString k; f dummyInj vv ks VNoval }; _ -> return vv })
          else lookup nameKey formatterTbl
    case formatter of
      Nothing -> do errs <- readIORef (iErrs inj); esz <- size errs; _ <- setprop errs (VNum (fromIntegral esz)) (VStr ("$FORMAT: unknown format: " ++ nameKey ++ ".")); return VNoval
      Just f -> do
        out <- walk (Just (\k vv _ _ -> f k vv)) Nothing VNoval resolved
        _ <- setprop target tkey out
        return out

-- | @$APPLY@ transform: apply a named transform.
transformApply :: Injector
transformApply inj _ _ store = do
  ok <- check_placement m_val "APPLY" t_list inj
  if not ok then return VNoval
  else do
    parent <- readIORef (iParent inj)
    sl <- sliceM parent (VNum 1) VNoval False
    res <- injector_args [t_function, t_any] sl
    let err = res !! 0
        applyFn = res !! 1
        child = if length res > 2 then res !! 2 else VNoval
    if not (isNoval err) then do errs <- readIORef (iErrs inj); esz <- size errs; es <- jsString err; _ <- setprop errs (VNum (fromIntegral esz)) (VStr ("$APPLY: " ++ es)); return VNoval
    else do
      path <- readIORef (iPath inj); tkey <- getelem path (VNum (-2))
      nodes <- readIORef (iNodes inj); target <- do t <- getelem nodes (VNum (-2)); if isNullish t then getelem nodes (VNum (-1)) else return t
      cinj <- inject_child child store inj
      resolved <- readIORef (iIval cinj)
      out <- case applyFn of VFunc f -> f cinj resolved "" store; _ -> return VNoval
      _ <- setprop target tkey out
      return out

-- | The default 'InjDef' used when the public API is called with 'INone'.
defaultInjDef :: Value -> InjDef
defaultInjDef errs = InjDef
  { dMeta = VNoval, dExtra = VNoval, dErrs = errs, dModify = Nothing, dHandler = Nothing
  , dBase = VNoval, dDparent = VNoval, dDpath = VNoval, dKey = VNoval }

-- | Run the transform engine: build output from a spec mirroring the shape, pulling from data via @\`...\`@.
transform :: InjArg -> Value -> Value -> IO Value
transform injarg dat spec0 = do
  let origspec = spec0
  spec <- clone spec0
  let extra = case injarg of IDef d -> dExtra d; _ -> VNoval
      collect = case injarg of IDef d -> not (isNoval (dErrs d)); _ -> False
  errs <- case injarg of IDef d | collect -> return (dErrs d); _ -> emptyList
  extraTransforms <- emptyMap
  extraData <- emptyMap
  when (not (isNoval extra)) $ do
    ps <- itemsPairs extra
    forM_ ps $ \(k, vv) -> if s_ds `isPrefixOf` k then setprop extraTransforms (VStr k) vv >> return () else setprop extraData (VStr k) vv >> return ()
  edEmpty <- isempty extraData
  ec <- if edEmpty then return VNoval else clone extraData
  dc <- clone dat
  ls <- mkList [ec, dc]
  dataClone <- merge ls
  store <- emptyMap
  let put k vv = setprop store (VStr k) vv >> return ()
  put s_dtop dataClone
  put s_dspec (VFunc (\_ _ _ _ -> return origspec))
  put "$BT" (VFunc (\_ _ _ _ -> return (VStr s_bt)))
  put "$DS" (VFunc (\_ _ _ _ -> return (VStr s_ds)))
  put "$WHEN" (VFunc (\_ _ _ _ -> return (VStr "1970-01-01T00:00:00.000Z")))
  put "$DELETE" (VFunc transformDelete)
  put "$COPY" (VFunc transformCopy)
  put "$KEY" (VFunc transformKey)
  put "$ANNO" (VFunc transformAnno)
  put "$MERGE" (VFunc transformMerge)
  put "$EACH" (VFunc transformEach)
  put "$PACK" (VFunc transformPack)
  put "$REF" (VFunc transformRef)
  put "$FORMAT" (VFunc transformFormat)
  put "$APPLY" (VFunc transformApply)
  etPairs <- itemsPairs extraTransforms
  forM_ etPairs $ \(k, vv) -> put k vv
  put s_derrs errs
  let idef0 = defaultInjDef errs
      idef = case injarg of
        IDef d -> idef0 { dMeta = dMeta d, dModify = dModify d, dHandler = dHandler d, dBase = dBase d }
        _ -> idef0
  out <- inject (IDef idef) spec store
  esz <- size errs
  when (esz > 0 && not collect) $ do j <- join errs (VStr " | ") False; throwIO (StructError j)
  return out

-- ---------------------------------------------------------------------------
-- validate
-- ---------------------------------------------------------------------------

-- | Append a validation error message to the injection state.
pushErr :: Inj -> String -> IO ()
pushErr inj msg = do errs <- readIORef (iErrs inj); esz <- size errs; _ <- setprop errs (VNum (fromIntegral esz)) (VStr msg); return ()

-- | Format the standard "invalid type" validation error message.
invalidTypeMsg :: Value -> String -> Int -> Value -> String -> IO String
invalidTypeMsg path needtype vt v _whence = do
  vs <- if isNullish v then return "no value" else stringify v
  psz <- size path
  fieldPart <- if psz > 1 then do p <- pathifyFull path (VNum 1) VNoval False; return ("field " ++ p ++ " to be ") else return ""
  let typePart = if not (isNullish v) then typename vt ++ s_viz else ""
  return ("Expected " ++ fieldPart ++ needtype ++ ", but found " ++ typePart ++ vs ++ ".")

-- | @$STRING@ validation rule.
validateString :: Injector
validateString inj _ _ _ = do
  dp <- readIORef (iDparent inj); k <- readIORef (iKey inj)
  out <- lookup_ dp k
  let t = typify out
  if (t_string .&. t) == 0 then do path <- readIORef (iPath inj); m <- invalidTypeMsg path s_string t out "V1010"; pushErr inj m; return VNoval
  else if vStrEq out s_mt then do path <- readIORef (iPath inj); p <- pathifyFull path (VNum 1) VNoval False; pushErr inj ("Empty string at " ++ p); return VNoval
  else return out

-- | Type-checking validation rule (@$NUMBER@, @$BOOLEAN@, ...).
validateType :: Injector
validateType inj _ refstr _ = do
  let tname = if length refstr > 1 then map toLower (drop 1 refstr) else "any"
      idx = fromMaybe (-1) (findIndex (== tname) typenameTbl)
      typev0 = if idx >= 0 then shiftL 1 (31 - idx) else 0
      typev = if tname == s_nil then typev0 .|. t_null else typev0
  dp <- readIORef (iDparent inj); k <- readIORef (iKey inj)
  out <- lookup_ dp k
  let t = typify out
  if (t .&. typev) == 0 then do path <- readIORef (iPath inj); m <- invalidTypeMsg path tname t out "V1001"; pushErr inj m; return VNoval
  else return out

-- | @$ANY@ validation rule (accept any value).
validateAny :: Injector
validateAny inj _ _ _ = do dp <- readIORef (iDparent inj); k <- readIORef (iKey inj); lookup_ dp k

-- | @$CHILD@ validation rule (validate each child against a template).
validateChild :: Injector
validateChild inj _ _ _ = do
  parent <- readIORef (iParent inj); key <- readIORef (iKey inj); path <- readIORef (iPath inj); keys <- readIORef (iKeys inj)
  mode <- readIORef (iMode inj)
  if mode == m_keypre then do
    childtm <- getprop parent key
    pkey <- getelem path (VNum (-2))
    dp <- readIORef (iDparent inj)
    tval <- getprop dp pkey
    if isNoval tval then do
      em <- emptyMap; eks <- keysof em
      forM_ eks $ \ckey -> do cc <- clone childtm; _ <- setprop parent (VStr ckey) cc; ksz <- size keys; _ <- setprop keys (VNum (fromIntegral ksz)) (VStr ckey); return ()
      _ <- delprop parent key; return VNoval
    else if not (ismap tval) then do
      psz <- size path; sl <- sliceM path (VNum 0) (VNum (fromIntegral (psz - 1))) False
      m <- invalidTypeMsg sl s_object (typify tval) tval "V0220"; pushErr inj m; return VNoval
    else do
      tks <- keysof tval
      forM_ tks $ \ckey -> do cc <- clone childtm; _ <- setprop parent (VStr ckey) cc; ksz <- size keys; _ <- setprop keys (VNum (fromIntegral ksz)) (VStr ckey); return ()
      _ <- delprop parent key; return VNoval
  else if mode == m_val then do
    childtm <- getprop parent (VNum 1)
    if not (islist parent) then do pushErr inj "Invalid $CHILD as value"; return VNoval
    else do
      dp <- readIORef (iDparent inj)
      if isNoval dp then case parent of VList r -> writeIORef r [] >> return VNoval; _ -> return VNoval
      else if not (islist dp) then do
        psz <- size path; sl <- sliceM path (VNum 0) (VNum (fromIntegral (psz - 1))) False
        m <- invalidTypeMsg sl s_list (typify dp) dp "V0230"; pushErr inj m
        psz2 <- size parent; writeIORef (iKeyi inj) psz2; return dp
      else do
        ps <- itemsPairs dp
        forM_ ps $ \(k, _) -> do cc <- clone childtm; _ <- setprop parent (VStr k) cc; return ()
        n <- size dp
        case parent of { VList r -> do { a <- readIORef r; writeIORef r (take (min n (length a)) a) }; _ -> return () }
        writeIORef (iKeyi inj) 0
        getprop dp (VNum 0)
  else return VNoval

-- | @$ONE@ validation rule (value must match one of the alternatives).
validateOne :: Injector
validateOne inj _ _ store = do
  mode <- readIORef (iMode inj)
  if mode == m_val then do
    parent <- readIORef (iParent inj)
    keyi <- readIORef (iKeyi inj)
    if not (islist parent) || keyi /= 0 then do
      path <- readIORef (iPath inj); p <- pathifyFull path (VNum 1) (VNum 1) False
      pushErr inj ("The $ONE validator at field " ++ p ++ " must be the first element of an array."); return VNoval
    else do
      keys <- readIORef (iKeys inj); ksz <- size keys; writeIORef (iKeyi inj) ksz
      dp <- readIORef (iDparent inj); _ <- injSetval 2 inj dp
      path <- readIORef (iPath inj); psz <- size path; sl <- sliceM path (VNum 0) (VNum (fromIntegral (psz - 1))) False; writeIORef (iPath inj) sl
      np <- readIORef (iPath inj); nk <- getelem np (VNum (-1)); writeIORef (iKey inj) nk
      tvals <- sliceM parent (VNum 1) VNoval False
      tsz <- size tvals
      if tsz == 0 then do path2 <- readIORef (iPath inj); p <- pathifyFull path2 (VNum 1) (VNum 1) False; pushErr inj ("The $ONE validator at field " ++ p ++ " must have at least one argument."); return VNoval
      else do
        matchedRef <- newIORef False
        tvItems <- listItems tvals
        forM_ tvItems $ \tval -> do
          matched <- readIORef matchedRef
          when (not matched) $ do
            terrs <- emptyList
            em <- emptyMap; ls <- mkList [em, store]; vstore <- mergeD ls (VNum 1)
            dp2 <- readIORef (iDparent inj); _ <- setprop vstore (VStr s_dtop) dp2
            meta <- readIORef (iMeta inj)
            let idef = (defaultInjDef terrs) { dExtra = vstore, dMeta = meta }
            vcurrent <- validate (IDef idef) dp2 tval
            _ <- injSetval (-2) inj vcurrent
            tesz <- size terrs
            when (tesz == 0) $ writeIORef matchedRef True
        matched <- readIORef matchedRef
        when (not matched) $ do
          ps <- itemsPairs tvals
          descs <- mapM (\(_, x) -> stringify x) ps
          let valdesc = replaceTransformNames (intercalate ", " descs)
          path3 <- readIORef (iPath inj); dp3 <- readIORef (iDparent inj)
          m <- invalidTypeMsg path3 ((if tsz > 1 then "one of " else "") ++ valdesc) (typify dp3) dp3 "V0210"
          pushErr inj m
        return VNoval
  else return VNoval

-- | @\`$EXACT\`@ validation rule (value must equal exactly).
validateExact :: Injector
validateExact inj _ _ _ = do
  mode <- readIORef (iMode inj)
  if mode == m_val then do
    parent <- readIORef (iParent inj); keyi <- readIORef (iKeyi inj)
    if not (islist parent) || keyi /= 0 then do path <- readIORef (iPath inj); p <- pathifyFull path (VNum 1) (VNum 1) False; pushErr inj ("The $EXACT validator at field " ++ p ++ " must be the first element of an array."); return VNoval
    else do
      keys <- readIORef (iKeys inj); ksz <- size keys; writeIORef (iKeyi inj) ksz
      dp <- readIORef (iDparent inj); _ <- injSetval 2 inj dp
      path <- readIORef (iPath inj); psz <- size path; sl <- sliceM path (VNum 0) (VNum (fromIntegral (psz - 1))) False; writeIORef (iPath inj) sl
      np <- readIORef (iPath inj); nk <- getelem np (VNum (-1)); writeIORef (iKey inj) nk
      tvals <- sliceM parent (VNum 1) VNoval False
      tsz <- size tvals
      if tsz == 0 then do path2 <- readIORef (iPath inj); p <- pathifyFull path2 (VNum 1) (VNum 1) False; pushErr inj ("The $EXACT validator at field " ++ p ++ " must have at least one argument."); return VNoval
      else do
        matchedRef <- newIORef False
        tvItems <- listItems tvals
        dp2 <- readIORef (iDparent inj)
        forM_ tvItems $ \tval -> do matched <- readIORef matchedRef; when (not matched) $ do eqb <- veq tval dp2; when eqb (writeIORef matchedRef True)
        matched <- readIORef matchedRef
        when (not matched) $ do
          ps <- itemsPairs tvals
          descs <- mapM (\(_, x) -> stringify x) ps
          let valdesc = replaceTransformNames (intercalate ", " descs)
          path3 <- readIORef (iPath inj); psz3 <- size path3
          m <- invalidTypeMsg path3 ((if psz3 > 1 then "" else "value ") ++ "exactly equal to " ++ (if tsz == 1 then "" else "one of ") ++ valdesc) (typify dp2) dp2 "V0110"
          pushErr inj m
        return VNoval
  else do p <- readIORef (iParent inj); k <- readIORef (iKey inj); _ <- delprop p k; return VNoval

-- | Deep structural equality of two values.
veq :: Value -> Value -> IO Bool
veq a b = case (a, b) of
  (VNoval, VNoval) -> return True
  (VNull, VNull) -> return True
  (VBool x, VBool y) -> return (x == y)
  (VNum x, VNum y) -> return (x == y)
  (VStr x, VStr y) -> return (x == y)
  (VSentinel x, VSentinel y) -> return (x == y)
  (VList x, VList y) -> do xs <- readIORef x; ys <- readIORef y; if length xs /= length ys then return False else andM (zipWith veq xs ys)
  (VMap x, VMap y) -> do xs <- readIORef x; ys <- readIORef y; if length xs /= length ys then return False else andM (map (\(k, vv) -> case lookup k ys of Just w -> veq vv w; Nothing -> return False) xs)
  _ -> return False

-- | The 'ModifyFn' that runs shape validation as the transform mutates.
validation :: ModifyFn
validation pval key parent inj = do
  when (not (is_skip pval)) $ do
    meta <- readIORef (iMeta inj)
    exact <- getpropAlt (VBool False) meta (VStr s_bexact)
    dp <- readIORef (iDparent inj)
    cval <- getprop dp key
    let exactB = case exact of VBool True -> True; _ -> False
    when (not ((not exactB) && isNoval cval)) $ do
      let ptype = typify pval
      pjs <- jsString pval
      when (not ((t_string .&. ptype) > 0 && '$' `elem` pjs)) $ do
        let ctype = typify cval
        path <- readIORef (iPath inj)
        if ptype /= ctype && not (isNoval pval) then do m <- invalidTypeMsg path (typename ptype) ctype cval "V0010"; pushErr inj m
        else if ismap cval then
          if not (ismap pval) then do m <- invalidTypeMsg path (typename ptype) ctype cval "V0020"; pushErr inj m
          else do
            ckeys <- keysof cval
            pkeys <- keysof pval
            bopenV <- getprop pval (VStr s_bopen)
            if not (null pkeys) && not (vIsTrue bopenV) then do
              badkeys <- filterM (\ck -> do lk <- lookup_ pval (VStr ck); return (isNoval lk)) ckeys
              when (not (null badkeys)) $ do p <- pathifyFull path (VNum 1) VNoval False; pushErr inj ("Unexpected keys at field " ++ p ++ s_viz ++ intercalate ", " badkeys)
            else do
              ls <- mkList [pval, cval]; _ <- merge ls
              when (isnode pval) (delprop pval (VStr s_bopen) >> return ())
        else if islist cval then when (not (islist pval)) $ do m <- invalidTypeMsg path (typename ptype) ctype cval "V0030"; pushErr inj m
        else if exactB then do
          eqb <- veq cval pval
          when (not eqb) $ do
            psz <- size path
            pathmsg <- if psz > 1 then do p <- pathifyFull path (VNum 1) VNoval False; return ("at field " ++ p ++ ": ") else return ""
            cjs <- jsString cval; pjs2 <- jsString pval
            pushErr inj ("Value " ++ pathmsg ++ cjs ++ " should equal " ++ pjs2 ++ ".")
        else do _ <- setprop parent key cval; return ()

-- | Injector handler used while validating.
validateHandler :: Injector
validateHandler inj v refstr store = case metaPathMatch refstr of
  Just (_, g2, _) -> do
    if g2 == "=" then do l <- mkList [VStr s_bexact, v]; _ <- injSetval1 inj l; return () else do _ <- injSetval1 inj v; return ()
    writeIORef (iKeyi inj) (-1)
    return skip
  Nothing -> injectHandler inj v refstr store

-- | Validate data against a shape, collecting errors; returns the (possibly defaulted) value.
validate :: InjArg -> Value -> Value -> IO Value
validate injarg dat spec = do
  let extra = case injarg of IDef d -> dExtra d; _ -> VNoval
      collect = case injarg of IDef d -> not (isNoval (dErrs d)); _ -> False
  errs <- case injarg of IDef d | collect -> return (dErrs d); _ -> emptyList
  base <- emptyMap
  let put k vv = setprop base (VStr k) vv >> return ()
  forM_ ["$DELETE", "$COPY", "$KEY", "$META", "$MERGE", "$EACH", "$PACK"] (\k -> put k VNull)
  put "$STRING" (VFunc validateString)
  forM_ ["$NUMBER", "$INTEGER", "$DECIMAL", "$BOOLEAN", "$NULL", "$NIL", "$MAP", "$LIST", "$FUNCTION", "$INSTANCE"] (\k -> put k (VFunc validateType))
  put "$ANY" (VFunc validateAny)
  put "$CHILD" (VFunc validateChild)
  put "$ONE" (VFunc validateOne)
  put "$EXACT" (VFunc validateExact)
  extraMap <- if isNoval extra then emptyMap else return extra
  errMap <- mkMap [(s_derrs, errs)]
  ls <- mkList [base, extraMap, errMap]; store <- mergeD ls (VNum 1)
  meta <- case injarg of IDef d | not (isNoval (dMeta d)) -> return (dMeta d); _ -> emptyMap
  bex <- getpropAlt (VBool False) meta (VStr s_bexact); _ <- setprop meta (VStr s_bexact) bex
  let idef = (defaultInjDef errs) { dMeta = meta, dExtra = store, dModify = Just validation, dHandler = Just validateHandler }
  out <- transform (IDef idef) dat spec
  esz <- size errs
  when (esz > 0 && not collect) $ do j <- join errs (VStr " | ") False; throwIO (StructError j)
  return out

-- ---------------------------------------------------------------------------
-- select
-- ---------------------------------------------------------------------------

-- | @$AND@ query operator.
selectAnd :: Injector
selectAnd inj _ _ store = do
  mode <- readIORef (iMode inj)
  when (mode == m_keypre) $ do
    parent <- readIORef (iParent inj); key <- readIORef (iKey inj)
    terms <- getprop parent key
    path <- readIORef (iPath inj); ppath <- sliceM path (VNum (-1)) VNoval False
    point <- getpath INone store ppath
    em <- emptyMap; ls <- mkList [em, store]; vstore <- mergeD ls (VNum 1)
    _ <- setprop vstore (VStr s_dtop) point
    ps <- itemsPairs terms
    forM_ ps $ \(_, term) -> do
      terrs <- emptyList
      meta <- readIORef (iMeta inj)
      let idef = (defaultInjDef terrs) { dExtra = vstore, dMeta = meta }
      _ <- validate (IDef idef) point term
      tesz <- size terrs
      when (tesz /= 0) $ do pp <- pathify ppath; sp <- stringify point; st <- stringify terms; pushErr inj ("AND:" ++ pp ++ cross ++ sp ++ " fail:" ++ st)
    gkey <- getelem path (VNum (-2))
    nodes <- readIORef (iNodes inj); gp <- getelem nodes (VNum (-2))
    _ <- setprop gp gkey point; return ()
  return VNoval

-- | @$OR@ query operator.
selectOr :: Injector
selectOr inj _ _ store = do
  mode <- readIORef (iMode inj)
  when (mode == m_keypre) $ do
    parent <- readIORef (iParent inj); key <- readIORef (iKey inj)
    terms <- getprop parent key
    path <- readIORef (iPath inj); ppath <- sliceM path (VNum (-1)) VNoval False
    point <- getpath INone store ppath
    em <- emptyMap; ls <- mkList [em, store]; vstore <- mergeD ls (VNum 1)
    _ <- setprop vstore (VStr s_dtop) point
    doneRef <- newIORef False
    ps <- itemsPairs terms
    forM_ ps $ \(_, term) -> do
      done <- readIORef doneRef
      when (not done) $ do
        terrs <- emptyList
        meta <- readIORef (iMeta inj)
        let idef = (defaultInjDef terrs) { dExtra = vstore, dMeta = meta }
        _ <- validate (IDef idef) point term
        tesz <- size terrs
        when (tesz == 0) $ do
          gkey <- getelem path (VNum (-2))
          nodes <- readIORef (iNodes inj); gp <- getelem nodes (VNum (-2))
          _ <- setprop gp gkey point; writeIORef doneRef True
    done <- readIORef doneRef
    when (not done) $ do pp <- pathify ppath; sp <- stringify point; st <- stringify terms; pushErr inj ("OR:" ++ pp ++ cross ++ sp ++ " fail:" ++ st)
  return VNoval

-- | @$NOT@ query operator.
selectNot :: Injector
selectNot inj _ _ store = do
  mode <- readIORef (iMode inj)
  when (mode == m_keypre) $ do
    parent <- readIORef (iParent inj); key <- readIORef (iKey inj)
    term <- getprop parent key
    path <- readIORef (iPath inj); ppath <- sliceM path (VNum (-1)) VNoval False
    point <- getpath INone store ppath
    em <- emptyMap; ls <- mkList [em, store]; vstore <- mergeD ls (VNum 1)
    _ <- setprop vstore (VStr s_dtop) point
    terrs <- emptyList
    meta <- readIORef (iMeta inj)
    let idef = (defaultInjDef terrs) { dExtra = vstore, dMeta = meta }
    _ <- validate (IDef idef) point term
    tesz <- size terrs
    when (tesz == 0) $ do pp <- pathify ppath; sp <- stringify point; st <- stringify term; pushErr inj ("NOT:" ++ pp ++ cross ++ sp ++ " fail:" ++ st)
    gkey <- getelem path (VNum (-2))
    nodes <- readIORef (iNodes inj); gp <- getelem nodes (VNum (-2))
    _ <- setprop gp gkey point; return ()
  return VNoval

-- | Apply a numeric comparison to two values (False unless both are numbers).
numCmp :: Value -> Value -> (Double -> Double -> Bool) -> Bool
numCmp a b op = case (a, b) of (VNum x, VNum y) -> op x y; _ -> False

-- | The @$LT@\/@$GT@\/@$LTE@\/@$GTE@\/@$EQ@ comparison query operators.
selectCmp :: Injector
selectCmp inj _ refstr store = do
  mode <- readIORef (iMode inj)
  when (mode == m_keypre) $ do
    parent <- readIORef (iParent inj); key <- readIORef (iKey inj)
    term <- getprop parent key
    path <- readIORef (iPath inj); gkey <- getelem path (VNum (-2))
    ppath <- sliceM path (VNum (-1)) VNoval False
    point <- getpath INone store ppath
    pass <- case refstr of
      "$GT" -> return (numCmp point term (>))
      "$LT" -> return (numCmp point term (<))
      "$GTE" -> return (numCmp point term (>=))
      "$LTE" -> return (numCmp point term (<=))
      "$LIKE" -> case term of { VStr t -> do { sp <- stringify point; return (Vregex.testStr t sp) }; _ -> return False }
      _ -> return False
    if pass then do nodes <- readIORef (iNodes inj); gp <- getelem nodes (VNum (-2)); _ <- setprop gp gkey point; return ()
    else do pp <- pathify ppath; sp <- stringify point; st <- stringify term; pushErr inj ("CMP: " ++ pp ++ cross ++ sp ++ " fail:" ++ refstr ++ " " ++ st)
  return VNoval

-- | Query a data structure with a by-example selection expression.
select :: Value -> Value -> IO Value
select children0 query =
  if not (isnode children0) then emptyList
  else do
    children <- if ismap children0
      then do ps <- itemsPairs children0; xs <- mapM (\(k, n) -> do _ <- setprop n (VStr s_dkey) (VStr k); return n) ps; mkList xs
      else do its <- listItems children0; xs <- mapM (\(i, n) -> if ismap n then do _ <- setprop n (VStr s_dkey) (vint i); return n else return n) (zip [0 ..] its); mkList xs
    results <- emptyList
    extra <- emptyMap
    forM_ [("$AND", selectAnd), ("$OR", selectOr), ("$NOT", selectNot), ("$GT", selectCmp), ("$LT", selectCmp), ("$GTE", selectCmp), ("$LTE", selectCmp), ("$LIKE", selectCmp)] $ \(k, f) -> setprop extra (VStr k) (VFunc f) >> return ()
    q <- clone query
    _ <- walk (Just (\_ vv _ _ -> do when (ismap vv) (do bo <- getpropAlt (VBool True) vv (VStr s_bopen); _ <- setprop vv (VStr s_bopen) bo; return ()); return vv)) Nothing VNoval q
    citems <- listItems children
    forM_ citems $ \child -> do
      errs <- emptyList
      meta <- emptyMap; _ <- setprop meta (VStr s_bexact) (VBool True)
      qc <- clone q
      let idef = (defaultInjDef errs) { dMeta = meta, dExtra = extra }
      _ <- validate (IDef idef) child qc
      esz <- size errs
      when (esz == 0) $ do rsz <- size results; _ <- setprop results (VNum (fromIntegral rsz)) child; return ()
    return results

-- ---------------------------------------------------------------------------
-- builders
-- ---------------------------------------------------------------------------

-- | Build a map node from a flat @[k1, v1, k2, v2, ...]@ value list.
jm :: [Value] -> IO Value
jm kv = do
  m <- emptyMap
  let go [] = return ()
      go (k0:rest) = do
        k <- case k0 of VNull -> return "null"; VStr s -> return s; _ -> stringify k0
        let (vv, rest') = case rest of (x:xs) -> (x, xs); [] -> (VNull, [])
        _ <- setprop m (VStr k) vv
        go rest'
  go kv
  return m

-- | Build a list node from the given values.
jt :: [Value] -> IO Value
jt = mkList

-- | Alias for 'typename'.
tn :: Int -> String
tn = typename
