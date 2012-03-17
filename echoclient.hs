{-# LANGUAGE OverloadedStrings #-}
module Main where
import System.ZMQ
import Prelude hiding(getContents, putStr, putStrLn)
import Data.ByteString.Char8 as BS
import qualified System.Network.ZMQ.MDP.Client as C
import Data.List as L


main :: IO ()
main = do
  input <- getContents
  C.withMDPClientSocket "tcp://127.0.0.1:5555" $ \s -> do
     res <- C.sendAndReceive s "echo" [input]
     putStr $ case res of
        Left err ->  case err of
                       C.MDPClientTimedOut    -> "Timed out!"
                       C.MDPClientBadProtocol -> "Bad protocol!"
        Right l ->  BS.concat . L.intersperse "\n" $ C.response l
