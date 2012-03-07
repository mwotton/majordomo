{-# LANGUAGE OverloadedStrings #-}
module Main where
import System.ZMQ
import Prelude hiding(getContents, putStr, putStrLn)
import Data.ByteString.Char8
import qualified MDWorker as W

main :: IO ()
main = withContext 1 $ \c ->
  W.start W.defaultWorker { W.svc     = "echo",
                            W.broker  = "tcp://127.0.0.1:5555",
                            W.handler = return,
                            W.context = c
                          }
      
    
    
    

      