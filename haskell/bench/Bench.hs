-- Performance bench for the Haskell port. Emits one JSON line per
-- build/bench/README.md; diagnostics go to stderr. The whole struct API runs
-- in IO (IORef-backed nodes), so the workload is built and timed in IO.
module Main where

import Data.IORef
import Data.List (intercalate, sort)
import Data.Version (showVersion)
import GHC.Clock (getMonotonicTimeNSec)
import System.Environment (lookupEnv)
import System.Info (compilerVersion)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)
import VoxgigStruct

envi :: String -> Int -> IO Int
envi k d = do
  m <- lookupEnv k
  return (maybe d id (m >>= readMaybe))

buildTree :: Int -> Int -> Int -> IO Value
buildTree w d leaf
  | d == 0 = return (VNum (fromIntegral leaf))
  | otherwise = do
      kids <- mapM (\i -> do { c <- buildTree w (d - 1) leaf; return ("k" ++ show i, c) })
                   [0 .. w - 1]
      mkMap kids

nodecount :: Int -> Int -> Int
nodecount w d = sum [w ^ i | i <- [0 .. d]]

-- (min, median, mean) in ms.
measure :: Int -> Int -> IO () -> IO (Double, Double, Double)
measure warm runs act = do
  mapM_ (const act) [1 .. warm]
  ts <- mapM (const timedOnce) [1 .. runs]
  let s = sort ts
      n = length s
  return (head s, s !! (n `div` 2), sum s / fromIntegral n)
  where
    timedOnce = do
      a <- getMonotonicTimeNSec
      act
      b <- getMonotonicTimeNSec
      return (fromIntegral (b - a) / 1e6 :: Double)

opJson :: String -> Int -> Int -> (Double, Double, Double) -> String
opJson op runs uc (mn, md, mean) =
  "{\"op\":\"" ++ op ++ "\",\"runs\":" ++ show runs
    ++ ",\"unit_count\":" ++ show uc
    ++ ",\"min_ms\":" ++ show mn
    ++ ",\"median_ms\":" ++ show md
    ++ ",\"mean_ms\":" ++ show mean ++ "}"

main :: IO ()
main = do
  w <- envi "BENCH_WIDTH" 5
  d <- envi "BENCH_DEPTH" 6
  warm <- envi "BENCH_WARMUP" 3
  runs <- envi "BENCH_RUNS" 21
  gp <- envi "BENCH_GETPATH_ITERS" 2000
  let nodes = nodecount w d
  tree <- buildTree w d 0
  treeA <- buildTree w d 1
  treeB <- buildTree w d 2
  mlist <- mkList [treeA, treeB]
  let pathv = VStr (intercalate "." (replicate d "k0"))
  sink <- newIORef (0 :: Int)
  let cb _key val _parent path = do
        n <- size path
        modifyIORef' sink (+ n)
        return val

  tClone <- measure warm runs (do c <- clone tree; c `seq` return ())
  tWalk <- measure warm runs (do _ <- walk (Just cb) Nothing VNoval tree; return ())
  tMerge <- measure warm runs (do _ <- merge mlist; return ())
  tStr <- measure warm runs (do s <- stringify tree; length s `seq` return ())
  tGet <- measure warm runs (loopGet gp pathv tree)

  sv <- readIORef sink
  hPutStrLn stderr ("haskell: sink=" ++ show sv)
  let ops = intercalate ","
        [ opJson "clone" runs nodes tClone
        , opJson "walk" runs nodes tWalk
        , opJson "merge" runs nodes tMerge
        , opJson "stringify" runs nodes tStr
        , opJson "getpath" runs gp tGet
        ]
  putStrLn $
    "{\"lang\":\"haskell\",\"runtime\":\"ghc " ++ showVersion compilerVersion
      ++ "\",\"nodes\":" ++ show nodes
      ++ ",\"params\":{\"width\":" ++ show w ++ ",\"depth\":" ++ show d
      ++ ",\"warmup\":" ++ show warm ++ ",\"runs\":" ++ show runs
      ++ ",\"getpath_iters\":" ++ show gp ++ "},\"ops\":[" ++ ops ++ "]}"

loopGet :: Int -> Value -> Value -> IO ()
loopGet 0 _ _ = return ()
loopGet k pathv tree = do
  _ <- getpath INone tree pathv
  loopGet (k - 1) pathv tree
