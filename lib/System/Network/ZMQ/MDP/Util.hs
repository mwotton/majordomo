{-# LANGUAGE OverloadedStrings #-}
module System.Network.ZMQ.MDP.Util where

import           System.ZMQ            as Z
import           Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as BS
import           Control.Applicative

-- Receive until no more messages
receiveUntilEnd :: Socket a -> IO [ByteString]
receiveUntilEnd sock = do
  more <- Z.moreToReceive sock
  if more
    then (:) <$> Z.receive sock [] <*> receiveUntilEnd sock
    else return []

-- Receive until an empty frame
receiveUntilEmpty :: Socket a -> IO [ByteString]
receiveUntilEmpty sock = do
  frame <- Z.receive sock []
  if BS.null frame
     then return []
     else (frame:) <$> receiveUntilEmpty sock

--
-- Sends a multipart message
--
sendAll :: Socket a -> [ByteString] -> IO ()
sendAll sock = go
  where go [x]    = Z.send sock x []
        go (x:xs) = Z.send sock x [SndMore] >> go xs
        go []     = error "empty send not allowed"