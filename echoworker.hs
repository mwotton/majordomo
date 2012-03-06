{-# LANGUAGE OverloadedStrings #-}
module Main where
import System.ZMQ
import Prelude hiding(getContents, putStr, putStrLn)
import Data.ByteString.Char8
import qualified MDWorker

main :: IO ()
main = withContext 1 $ \c ->
  withSocket c XReq $ \sock -> do
    connect sock "tcp://127.0.0.1:5555"
    putStrLn "connected"
    MDWorker.start sock "echo" (return)

      
    
    
    

      