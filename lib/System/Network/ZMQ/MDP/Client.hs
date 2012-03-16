{-# LANGUAGE OverloadedStrings #-}
module System.Network.ZMQ.MDP.Client (
  -- | Types
  Response(..),
  MDPClientSocket, -- opaque datatype 

  -- | Functions
  send,
  withMDPClientSocket

) where

import Data.ByteString.Char8
import qualified System.ZMQ as Z
import System.ZMQ hiding(send)
import Control.Applicative
import System.Timeout

data Protocol = MDCP01

data Response = Response { protocol :: Protocol,
                           service :: ByteString,
                           response :: [ByteString] }

data MDPClientSocket = MDPClientSocket { mdpClientSocket :: Socket Req }

withMDPClientSocket :: String -> (MDPClientSocket -> IO a) -> IO a
withMDPClientSocket socketAddress io =
 withContext 1 $ \c -> withSocket c Req $ \s -> do
   connect s socketAddress
   io (MDPClientSocket s)

send :: MDPClientSocket -> ByteString -> [ByteString] -> IO (Either ByteString Response)
send mdpcs service msgs =
  do Z.send sock "MDPC01"  [SndMore]
     Z.send sock service   [SndMore]
     sendAll sock msgs
     maybeprot <- timeout (1000000 * 3) $ receive sock []
     case maybeprot of
       Nothing -> return $ Left "Timed out!"
       Just "MDPC01" -> do
         res <- Response MDCP01 <$> receive sock [] <*> receiveTillEmpty sock
         return $ Right res
       _ -> return $ Left "bad protocol"
  where
    sock = mdpClientSocket mdpcs

--
-- Helper functions
--

receiveTillEmpty :: Socket a -> IO [ByteString]
receiveTillEmpty sock = do
  more <- Z.moreToReceive sock
  if more
    then (:) <$> receive sock [] <*> receiveTillEmpty sock
    else return []

--
-- Sends a multipart message
--
sendAll :: Socket a -> [ByteString] -> IO ()
sendAll sock []     = return ()
sendAll sock (m:[]) = Z.send sock m []
sendAll sock (m:ms) = Z.send sock m [SndMore] >> sendAll sock ms