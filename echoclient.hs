{-# LANGUAGE OverloadedStrings #-}
module Main where
import System.ZMQ
import Prelude hiding(getContents, putStr, putStrLn)
import Data.ByteString.Char8
import qualified MDCli

main :: IO ()
main = do
  input <- getContents
  withContext 1 $ \c ->
    withSocket c Req $ \sock -> do
      connect sock "tcp://*:5555"
      res <- MDCli.send sock input
      putStr $ case res of
        Left l ->  "Bad response: " `append` l
        Right l ->  MDCli.response l
      
    
    
    

      