{-# LANGUAGE OverloadedStrings #-}
module Main where
import System.ZMQ
import Prelude hiding(getContents, putStr, putStrLn)
import Data.ByteString.Char8 as BS
import qualified System.Network.ZMQ.MDP.Client as MDCli
import Data.List as L


main :: IO ()
main = do
  input <- getContents
  withContext 1 $ \c ->
    withSocket c Req $ \sock -> do
      connect sock "tcp://127.0.0.1:5555"
      res <- MDCli.send sock "echo" [input]
      putStr $ case res of
        Left l ->  "Bad response: " `append` l
        Right l ->  BS.concat . L.intersperse "\n" $ MDCli.response l
