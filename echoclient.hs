{-# LANGUAGE OverloadedStrings, DeriveDataTypeable #-}
module Main where

import Prelude hiding(getContents, putStr, putStrLn)
import Data.ByteString.Char8 as BS
import qualified System.Network.ZMQ.MDP.Client as C
import Data.List as L
import System.Console.CmdArgs.Implicit

data Client = Client {broker :: String, 
                      service::String, 
                      message_parts::[String]} deriving (Show, Data, Typeable)


client :: Client
client = Client{ broker        = def &= argPos 0 ,
                 service       = def &= argPos 1 ,
                 message_parts = def &= args 
                 } &= summary "connect to a 0mq server"


main :: IO ()
main = do 
  s <- cmdArgs client
  print s
  C.withMDPClientSocket (broker s) $ \sock -> do
      res <- C.send sock (pack $ service s) (Prelude.map pack $ message_parts s)
      putStr $ case res of
        Left l ->  "Bad response: " `append` l
        Right l ->  BS.concat . L.intersperse "\n" $ C.response l

