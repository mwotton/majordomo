{-# LANGUAGE OverloadedStrings #-}
module Main where
import Data.ByteString hiding (map)

import qualified System.Network.ZMQ.MDP.Worker as W
import Data.Foldable
import Control.Concurrent.Thread.Group as TG
import System.Posix.Signals
import qualified Control.Concurrent as CC

threaded :: [IO ()] -> IO ()
threaded actions = do
  tg <- TG.new
  tids <- mapM (TG.forkIO tg)  actions
  _ <- installHandler sigINT (CatchOnce $ do
        Prelude.putStrLn "worker caught an interrupt"
        forM_ tids ((\x -> print x  >> CC.killThread x) . fst)
        ) Nothing
  Prelude.putStrLn "waiting..."
  TG.wait tg
  Prelude.putStrLn "all dead"

main :: IO ()
main = threaded $ flip map [1..4] $ \tid ->
  W.withWorker "tcp://127.0.0.1:5555" "echo"
               (\x ->  return ("hi there, " `append` x))

 
 -- withContext 1 $ \c ->
 --    threaded $ flip map [1..4] $ \tid ->
 --      W.start W.defaultWorker {                            }