-- Smoke test for the Haskell test provider port. Prints summary stats that
-- must match the canonical TS output documented in PROVIDER work.
--
-- NOTE: GHC is unavailable in this environment; this has NOT been compiled or
-- executed. The expected output (per the task) is:
--
--   functions: minor, getpath, inject, merge, transform, walk, validate, select, sentinels
--   total entries: 1325
--   expect kinds: value=1181, absent=84, match=1, error=59
--   input kinds: in=1325
--   getpath/basic[0]: id=getpath/basic#deep, doc=true, input.kind=in,
--                     expect.kind=value, expect.value=42

module Main (main) where

import Data.List (sort)

import Provider

main :: IO ()
main = do
  prov <- load Nothing

  let fns = functions prov
  putStrLn ("functions: " ++ intercalate ", " fns)

  let allEntries = concatMap (\fn -> entries prov fn Nothing) fns
      total = length allEntries
      ekTallies = tally (map (expectKindName . ekind . expect) allEntries)
      ikTallies = tally (map (inputKindName . ikind . input) allEntries)

  putStrLn ("total entries: " ++ show total)
  putStrLn ("expect kinds: " ++ renderTally ekTallies)
  putStrLn ("input kinds: " ++ renderTally ikTallies)

  let e = head (entries prov "getpath" (Just "basic"))
  putStrLn $
    "getpath/basic[0]: "
      ++ "id=" ++ maybe "null" id (eid e)
      ++ ", doc=" ++ boolStr (doc e)
      ++ ", input.kind=" ++ inputKindName (ikind (input e))
      ++ ", expect.kind=" ++ expectKindName (ekind (expect e))
      ++ ", expect.value=" ++ maybe "null" stringify (evalue (expect e))

  -- helper sanity checks
  putStrLn ("equal(null, null) lenient: " ++ boolStr (equal JNull JNull))
  putStrLn
    ( "equalStrict null vs __NULL__-collapse: "
        ++ boolStr (equalStrict JNull (JStr "__NULL__"))
        ++ " / "
        ++ boolStr (equalStrict JNull (JNum 1))
    )
  putStrLn
    ( "errorMatches substring case-insensitive: "
        ++ boolStr (errorMatches (ErrorCheck False (Just "Foo") False) "a foobar error")
    )
  let sm = structMatch (JObj [("a", JObj [("b", JNum 2)])])
                        (JObj [("a", JObj [("b", JNum 3)])])
  putStrLn ("structMatch failure: " ++ showMatch sm)

-- ─── helpers ────────────────────────────────────────────────────────────────

expectKindName :: ExpectKind -> String
expectKindName EValue  = "value"
expectKindName EError  = "error"
expectKindName EMatch  = "match"
expectKindName EAbsent = "absent"

inputKindName :: InputKind -> String
inputKindName KIn   = "in"
inputKindName KArgs = "args"
inputKindName KCtx  = "ctx"

boolStr :: Bool -> String
boolStr True  = "true"
boolStr False = "false"

-- Count occurrences, returning (key, count) sorted by key (matches the Python
-- smoke's `sorted(kinds)` ordering).
tally :: [String] -> [(String, Int)]
tally xs = [(k, length (filter (== k) xs)) | k <- sort (uniq xs)]

uniq :: [String] -> [String]
uniq = go []
  where
    go seen [] = reverse seen
    go seen (x : rest)
      | x `elem` seen = go seen rest
      | otherwise     = go (x : seen) rest

renderTally :: [(String, Int)] -> String
renderTally ts = intercalate ", " [k ++ "=" ++ show v | (k, v) <- ts]

intercalate :: String -> [String] -> String
intercalate _ []       = ""
intercalate _ [x]      = x
intercalate sep (x:xs) = x ++ sep ++ intercalate sep xs

showMatch :: MatchResult -> String
showMatch m =
  "{ok=" ++ boolStr (ok m)
    ++ ", path=[" ++ intercalate "," (mpath m) ++ "]"
    ++ ", expected=" ++ maybe "-" stringify (mexpected m)
    ++ ", actual=" ++ maybe "-" stringify (mactual m)
    ++ "}"
