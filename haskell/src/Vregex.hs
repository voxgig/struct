-- Minimal backtracking regex engine for the Haskell port of voxgig/struct.
-- Supports the RE2 subset the corpus exercises: literals, '.', anchors ^ $,
-- \b, character classes [..] / [^..] with ranges and \d \w \s \D \W \S,
-- groups (..) and (?:..), alternation |, quantifiers * + ? and {n}/{n,}/{n,m}
-- with optional lazy '?'. No third-party dependency. The struct library uses
-- `test` for $LIKE; `find` backs the public re_* API (not corpus-tested).

module Vregex
  ( Re
  , compile
  , test
  , testStr
  , findBounds
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
  | Cls Bool [Citem]              -- negated?, items
  | Grp [[Node]]                  -- alternation of sequences
  | Star Bool Node               -- greedy?, atom
  | Plus Bool Node
  | Opt Bool Node
  | Rep Bool Int (Maybe Int) Node

data Citem
  = CChar Char
  | CRange Char Char
  | CD | CW | CS | CND | CNW | CNS  -- \d \w \s \D \W \S

-- ----- parser (remaining-string style) -----

parse :: String -> [[Node]]
parse pat = fst (parseAlt pat)

parseAlt :: String -> ([[Node]], String)
parseAlt s0 =
  let (first, s1) = parseSeq s0
  in go [first] s1
  where
    go acc ('|':rest) = let (sq, r) = parseSeq rest in go (sq : acc) r
    go acc r = (reverse acc, r)

parseSeq :: String -> ([Node], String)
parseSeq = goSeq []
  where
    goSeq acc s = case s of
      [] -> (reverse acc, s)
      ('|':_) -> (reverse acc, s)
      (')':_) -> (reverse acc, s)
      _ -> case parseAtom s of
             (Nothing, s') -> (reverse acc, s')
             (Just a, s') ->
               let (a', s'') = parseQuantSuffix a s'
               in goSeq (a' : acc) s''

parseAtom :: String -> (Maybe Node, String)
parseAtom s = case s of
  [] -> (Nothing, s)
  ('(':rest) ->
    let rest1 = case rest of ('?':':':r) -> r; _ -> rest
        (alts, r2) = parseAlt rest1
        r3 = case r2 of (')':r) -> r; _ -> r2
    in (Just (Grp alts), r3)
  ('[':_) -> let (n, r) = parseClass s in (Just n, r)
  ('.':rest) -> (Just Any, rest)
  ('^':rest) -> (Just Start, rest)
  ('$':rest) -> (Just End, rest)
  ('\\':rest) -> case rest of
    ('d':r) -> (Just (Cls False [CD]), r)
    ('w':r) -> (Just (Cls False [CW]), r)
    ('s':r) -> (Just (Cls False [CS]), r)
    ('D':r) -> (Just (Cls False [CND]), r)
    ('W':r) -> (Just (Cls False [CNW]), r)
    ('S':r) -> (Just (Cls False [CNS]), r)
    ('b':r) -> (Just WordB, r)
    ('n':r) -> (Just (Char '\n'), r)
    ('t':r) -> (Just (Char '\t'), r)
    ('r':r) -> (Just (Char '\r'), r)
    (c:r) -> (Just (Char c), r)
    [] -> (Just (Char '\\'), [])
  (c:rest) -> (Just (Char c), rest)

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

-- ----- matcher (backtracking, CPS over Maybe) -----

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

mNode :: (Int -> Char) -> Int -> Node -> Int -> (Int -> Maybe r) -> Maybe r
mNode inp len node pos k = case node of
  Char c -> if pos < len && inp pos == c then k (pos + 1) else Nothing
  Any -> if pos < len && inp pos /= '\n' then k (pos + 1) else Nothing
  Start -> if pos == 0 then k pos else Nothing
  End -> if pos == len then k pos else Nothing
  WordB ->
    let before = pos > 0 && isWord (inp (pos - 1))
        after = pos < len && isWord (inp pos)
    in if before /= after then k pos else Nothing
  Cls neg items ->
    if pos < len
      then let c = inp pos
               hit = any (`citemMatch` c) items
           in if (if neg then not hit else hit) then k (pos + 1) else Nothing
      else Nothing
  Grp alts -> asum [mSeq inp len sq pos k | sq <- alts]
  Opt greedy a ->
    if greedy then mNode inp len a pos k <|> k pos
    else k pos <|> mNode inp len a pos k
  Star greedy a -> mStar inp len greedy a pos k
  Plus greedy a -> mNode inp len a pos (\p -> mStar inp len greedy a p k)
  Rep greedy mn mx a -> mRep inp len greedy mn mx a pos k

mStar :: (Int -> Char) -> Int -> Bool -> Node -> Int -> (Int -> Maybe r) -> Maybe r
mStar inp len greedy a pos k =
  if greedy
    then mNode inp len a pos (\p -> if p > pos then mStar inp len greedy a p k else Nothing) <|> k pos
    else k pos <|> mNode inp len a pos (\p -> if p > pos then mStar inp len greedy a p k else Nothing)

mRep :: (Int -> Char) -> Int -> Bool -> Int -> Maybe Int -> Node -> Int -> (Int -> Maybe r) -> Maybe r
mRep inp len greedy mn mx a pos k =
  if mn > 0
    then mNode inp len a pos (\p -> mRep inp len greedy (mn - 1) (fmap (subtract 1) mx) a p k)
    else case mx of
      Just 0 -> k pos
      _ ->
        let next p = if p > pos then mRep inp len greedy 0 (fmap (subtract 1) mx) a p k else Nothing
        in if greedy then mNode inp len a pos next <|> k pos
           else k pos <|> mNode inp len a pos next

mSeq :: (Int -> Char) -> Int -> [Node] -> Int -> (Int -> Maybe r) -> Maybe r
mSeq inp len sq pos k = case sq of
  [] -> k pos
  (x:rest) -> mNode inp len x pos (\p -> mSeq inp len rest p k)

-- Compiled = the alternation AST.
type Re = [[Node]]

compile :: String -> Re
compile = parse

mkInp :: String -> (Int -> Char, Int)
mkInp input =
  let len = length input
      arr = listArray (0, len - 1) input :: Array Int Char
  in ((arr !), len)

-- Does the pattern match anywhere in input?
test :: Re -> String -> Bool
test re input = tryAt 0
  where
    (inp, len) = mkInp input
    tryAt i
      | any (\sq -> isJust (mSeq inp len sq i (\_ -> Just ()))) re = True
      | i >= len = False
      | otherwise = tryAt (i + 1)

testStr :: String -> String -> Bool
testStr pat input = test (compile pat) input

-- Leftmost match: returns (start, stop) or Nothing. Used by the public re_* API.
findBounds :: Re -> String -> Maybe (Int, Int)
findBounds re input = tryAt 0
  where
    (inp, len) = mkInp input
    tryAt i
      | i > len = Nothing
      | otherwise = case asum [mSeq inp len sq i Just | sq <- re] of
          Just p -> Just (i, p)
          Nothing -> tryAt (i + 1)
