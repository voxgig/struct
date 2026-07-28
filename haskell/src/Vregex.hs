-- Minimal backtracking regex engine for the Haskell port of voxgig/struct.
-- Supports the RE2 subset the corpus exercises: literals, '.', anchors ^ $,
-- \b and \B, character classes [..] / [^..] with ranges and \d \w \s \D \W \S,
-- groups (..), (?:..) and (?P<name>..), alternation |, quantifiers * + ? and
-- {n}/{n,}/{n,m} with optional lazy '?'. Capturing groups are tracked, so the
-- engine backs the full re_* API (find with captures, find_all, replace) at
-- the Go-stdlib minimum bar; `test` also serves $LIKE. No third-party
-- dependency.

module Vregex
  ( Re
  , compile
  , test
  , testStr
  , findBounds
  , find
  , findAll
  , replaceAll
  ) where

import Control.Applicative ((<|>))
import Data.Array (Array, listArray, (!))
import Data.Foldable (asum)
import Data.Maybe (isJust)

data Node
  = Char Char
  | Any
  | Start
  | End
  | WordB
  | NWordB
  | Cls Bool [Citem]              -- negated?, items
  | Grp Int [[Node]]              -- capture index (0 = non-capturing), alternation
  | Star Bool Node               -- greedy?, atom
  | Plus Bool Node
  | Opt Bool Node
  | Rep Bool Int (Maybe Int) Node

data Citem
  = CChar Char
  | CRange Char Char
  | CD | CW | CS | CND | CNW | CNS  -- \d \w \s \D \W \S

-- Compiled = the alternation AST plus the number of capturing groups.
data Re = Re { reAlts :: [[Node]], reNgroups :: Int }

-- ----- parser (remaining-string style, threading the group counter) -----

parse :: String -> Re
parse pat = let (alts, gc, _) = parseAlt 0 pat in Re alts gc

parseAlt :: Int -> String -> ([[Node]], Int, String)
parseAlt gc0 s0 =
  let (first, gc1, s1) = parseSeq gc0 s0
  in go [first] gc1 s1
  where
    go acc gc ('|':rest) = let (sq, gc', r) = parseSeq gc rest in go (sq : acc) gc' r
    go acc gc r = (reverse acc, gc, r)

parseSeq :: Int -> String -> ([Node], Int, String)
parseSeq = goSeq []
  where
    goSeq acc gc s = case s of
      [] -> (reverse acc, gc, s)
      ('|':_) -> (reverse acc, gc, s)
      (')':_) -> (reverse acc, gc, s)
      _ -> case parseAtom gc s of
             (Nothing, gc', s') -> (reverse acc, gc', s')
             (Just a, gc', s') ->
               let (a', s'') = parseQuantSuffix a s'
               in goSeq (a' : acc) gc' s''

parseAtom :: Int -> String -> (Maybe Node, Int, String)
parseAtom gc s = case s of
  [] -> (Nothing, gc, s)
  ('(':rest) ->
    -- (?: is non-capturing; a plain ( and an RE2 named group (?P<name> are
    -- both capturing (names are not tracked). Indices follow open parens.
    let (gi, gc1, rest1) = case rest of
          ('?':':':r) -> (0, gc, r)
          ('?':'P':'<':r) ->
            let r' = drop 1 (dropWhile (/= '>') r)
            in (gc + 1, gc + 1, r')
          _ -> (gc + 1, gc + 1, rest)
        (alts, gc2, r2) = parseAlt gc1 rest1
        r3 = case r2 of (')':r) -> r; _ -> r2
    in (Just (Grp gi alts), gc2, r3)
  ('[':_) -> let (n, r) = parseClass s in (Just n, gc, r)
  ('.':rest) -> (Just Any, gc, rest)
  ('^':rest) -> (Just Start, gc, rest)
  ('$':rest) -> (Just End, gc, rest)
  ('\\':rest) -> case rest of
    ('d':r) -> (Just (Cls False [CD]), gc, r)
    ('w':r) -> (Just (Cls False [CW]), gc, r)
    ('s':r) -> (Just (Cls False [CS]), gc, r)
    ('D':r) -> (Just (Cls False [CND]), gc, r)
    ('W':r) -> (Just (Cls False [CNW]), gc, r)
    ('S':r) -> (Just (Cls False [CNS]), gc, r)
    ('b':r) -> (Just WordB, gc, r)
    ('B':r) -> (Just NWordB, gc, r)
    ('n':r) -> (Just (Char '\n'), gc, r)
    ('t':r) -> (Just (Char '\t'), gc, r)
    ('r':r) -> (Just (Char '\r'), gc, r)
    (c:r) -> (Just (Char c), gc, r)
    [] -> (Just (Char '\\'), gc, [])
  (c:rest) -> (Just (Char c), gc, rest)

parseClass :: String -> (Node, String)
parseClass ('[':s0) =
  let (neg, s1) = case s0 of ('^':r) -> (True, r); _ -> (False, s0)
      (items, rest) = goCls [] s1
  in (Cls neg (reverse items), rest)
  where
    goCls acc s = case s of
      [] -> (acc, s)
      (']':r) -> (acc, r)
      ('\\':r) -> case r of
        ('d':r') -> goCls (CD : acc) r'
        ('w':r') -> goCls (CW : acc) r'
        ('s':r') -> goCls (CS : acc) r'
        ('D':r') -> goCls (CND : acc) r'
        ('W':r') -> goCls (CNW : acc) r'
        ('S':r') -> goCls (CNS : acc) r'
        ('n':r') -> goCls (CChar '\n' : acc) r'
        ('t':r') -> goCls (CChar '\t' : acc) r'
        ('r':r') -> goCls (CChar '\r' : acc) r'
        (c:r') -> goCls (CChar c : acc) r'
        [] -> (acc, [])
      (c : '-' : c2 : r) | c2 /= ']' -> goCls (CRange c c2 : acc) r
      (c:r) -> goCls (CChar c : acc) r
parseClass s = (Cls False [], s)

parseQuantSuffix :: Node -> String -> (Node, String)
parseQuantSuffix atom s = case s of
  ('*':rest) -> let (lz, r) = lazyq rest in (Star (not lz) atom, r)
  ('+':rest) -> let (lz, r) = lazyq rest in (Plus (not lz) atom, r)
  ('?':rest) -> let (lz, r) = lazyq rest in (Opt (not lz) atom, r)
  ('{':rest) ->
    let (mn, r1) = num rest
        (mx, r2) = case r1 of
          (',':r) -> let (s2, r') = num r in (if null s2 then Nothing else Just (read s2), r')
          _ -> (Just (if null mn then 0 else read mn), r1)
    in case r2 of
         ('}':r3) | not (null mn) ->
           let (lz, r4) = lazyq r3 in (Rep (not lz) (read mn) mx atom, r4)
         _ -> (atom, s)
  _ -> (atom, s)
  where
    lazyq ('?':r) = (True, r)
    lazyq r = (False, r)
    num = span (\c -> c >= '0' && c <= '9')

-- ----- matcher (backtracking, CPS over Maybe, capture-tracking) -----

isWord :: Char -> Bool
isWord c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
        || (c >= '0' && c <= '9') || c == '_'

spaceChars :: String
spaceChars = [' ', '\t', '\n', '\r', '\f', '\v']

citemMatch :: Citem -> Char -> Bool
citemMatch it c = case it of
  CChar x -> c == x
  CRange a b -> c >= a && c <= b
  CD -> c >= '0' && c <= '9'
  CND -> not (c >= '0' && c <= '9')
  CW -> isWord c
  CNW -> not (isWord c)
  CS -> c `elem` spaceChars
  CNS -> not (c `elem` spaceChars)

-- Capture spans as an association list; a group re-recorded on a later
-- iteration is simply prepended, so `lookup` sees the most recent span.
-- Spans are threaded functionally, so backtracking naturally discards
-- abandoned group records.
type Caps = [(Int, (Int, Int))]

mNode :: (Int -> Char) -> Int -> Node -> Int -> Caps -> (Int -> Caps -> Maybe r) -> Maybe r
mNode inp len node pos caps k = case node of
  Char c -> if pos < len && inp pos == c then k (pos + 1) caps else Nothing
  Any -> if pos < len && inp pos /= '\n' then k (pos + 1) caps else Nothing
  Start -> if pos == 0 then k pos caps else Nothing
  End -> if pos == len then k pos caps else Nothing
  WordB ->
    let before = pos > 0 && isWord (inp (pos - 1))
        after = pos < len && isWord (inp pos)
    in if before /= after then k pos caps else Nothing
  NWordB ->
    let before = pos > 0 && isWord (inp (pos - 1))
        after = pos < len && isWord (inp pos)
    in if before == after then k pos caps else Nothing
  Cls neg items ->
    if pos < len
      then let c = inp pos
               hit = any (`citemMatch` c) items
           in if (if neg then not hit else hit) then k (pos + 1) caps else Nothing
      else Nothing
  Grp gi alts ->
    let k' = if gi == 0 then k
             else \p caps' -> k p ((gi, (pos, p)) : caps')
    in asum [mSeq inp len sq pos caps k' | sq <- alts]
  Opt greedy a ->
    if greedy then mNode inp len a pos caps k <|> k pos caps
    else k pos caps <|> mNode inp len a pos caps k
  Star greedy a -> mStar inp len greedy a pos caps k
  Plus greedy a -> mNode inp len a pos caps (\p c -> mStar inp len greedy a p c k)
  Rep greedy mn mx a -> mRep inp len greedy mn mx a pos caps k

mStar :: (Int -> Char) -> Int -> Bool -> Node -> Int -> Caps -> (Int -> Caps -> Maybe r) -> Maybe r
mStar inp len greedy a pos caps k =
  let more p c = if p > pos then mStar inp len greedy a p c k else Nothing
  in if greedy
    then mNode inp len a pos caps more <|> k pos caps
    else k pos caps <|> mNode inp len a pos caps more

mRep :: (Int -> Char) -> Int -> Bool -> Int -> Maybe Int -> Node -> Int -> Caps -> (Int -> Caps -> Maybe r) -> Maybe r
mRep inp len greedy mn mx a pos caps k =
  if mn > 0
    then mNode inp len a pos caps (\p c -> mRep inp len greedy (mn - 1) (fmap (subtract 1) mx) a p c k)
    else case mx of
      Just 0 -> k pos caps
      _ ->
        let next p c = if p > pos then mRep inp len greedy 0 (fmap (subtract 1) mx) a p c k else Nothing
        in if greedy then mNode inp len a pos caps next <|> k pos caps
           else k pos caps <|> mNode inp len a pos caps next

mSeq :: (Int -> Char) -> Int -> [Node] -> Int -> Caps -> (Int -> Caps -> Maybe r) -> Maybe r
mSeq inp len sq pos caps k = case sq of
  [] -> k pos caps
  (x:rest) -> mNode inp len x pos caps (\p c -> mSeq inp len rest p c k)

compile :: String -> Re
compile = parse

mkInp :: String -> (Int -> Char, Int)
mkInp input =
  let len = length input
      arr = listArray (0, len - 1) input :: Array Int Char
  in ((arr !), len)

-- First match at or after `start`: (mstart, mend, caps).
findAt :: Re -> (Int -> Char) -> Int -> Int -> Maybe (Int, Int, Caps)
findAt re inp len = tryAt
  where
    tryAt i
      | i > len = Nothing
      | otherwise = case asum [mSeq inp len sq i [] (\p c -> Just (p, c)) | sq <- reAlts re] of
          Just (e, caps) -> Just (i, e, caps)
          Nothing -> tryAt (i + 1)

-- Does the pattern match anywhere in input?
test :: Re -> String -> Bool
test re input = let (inp, len) = mkInp input in isJust (findAt re inp len 0)

testStr :: String -> String -> Bool
testStr pat input = test (compile pat) input

-- Leftmost match: returns (start, stop) or Nothing.
findBounds :: Re -> String -> Maybe (Int, Int)
findBounds re input =
  let (inp, len) = mkInp input
  in fmap (\(s, e, _) -> (s, e)) (findAt re inp len 0)

subStr :: String -> Int -> Int -> String
subStr input a b = take (b - a) (drop a input)

matchGroups :: Re -> String -> Int -> Int -> Caps -> [String]
matchGroups re input ms me caps =
  subStr input ms me
    : [ maybe "" (\(a, b) -> subStr input a b) (lookup gi caps)
      | gi <- [1 .. reNgroups re] ]

-- First match as [whole, capture1, ...]; unmatched groups are "".
find :: Re -> String -> Maybe [String]
find re input =
  let (inp, len) = mkInp input
  in fmap (\(ms, me, caps) -> matchGroups re input ms me caps) (findAt re inp len 0)

-- Every non-overlapping match, left to right (Go FindAllStringSubmatch).
findAll :: Re -> String -> [[String]]
findAll re input = go 0
  where
    (inp, len) = mkInp input
    go pos
      | pos > len = []
      | otherwise = case findAt re inp len pos of
          Nothing -> []
          Just (ms, me, caps) ->
            matchGroups re input ms me caps
              : go (if me == ms then me + 1 else me)

-- Replace every match; the template supports JS-style refs ($& for the whole
-- match, $1..$9 for captures, $$ for a literal $). On a zero-width match the
-- current character is emitted and the scan advances one position.
replaceAll :: Re -> String -> String -> String
replaceAll re input template = go 0
  where
    (inp, len) = mkInp input
    go pos
      | pos > len = ""
      | otherwise = case findAt re inp len pos of
          Nothing -> subStr input pos len
          Just (ms, me, caps) ->
            subStr input pos ms
              ++ expand ms me caps template
              ++ (if me == ms
                    then (if ms < len then [inp ms] else "") ++ go (ms + 1)
                    else go me)
    expand _ _ _ [] = []
    expand ms me caps ('$':'$':r) = '$' : expand ms me caps r
    expand ms me caps ('$':'&':r) = subStr input ms me ++ expand ms me caps r
    expand ms me caps ('$':d:r)
      | d >= '0' && d <= '9' =
          let gi = fromEnum d - fromEnum '0'
              part
                | gi == 0 = subStr input ms me
                | gi <= reNgroups re =
                    maybe "" (\(a, b) -> subStr input a b) (lookup gi caps)
                | otherwise = ""
          in part ++ expand ms me caps r
    expand ms me caps (c:r) = c : expand ms me caps r
