{-# LANGUAGE OverloadedStrings #-}
module System.Network.ZMQ.MDP.Client (
  -- | Types
  Response(..),
  ClientSocket, -- opaque datatype 
  ClientError(..),
  -- | Functions
  sendAndReceive,
  withClientSocket
) where

-- libraries
import Data.ByteString.Char8
import qualified System.ZMQ as Z
import System.ZMQ hiding(send)
import Control.Applicative
import System.Timeout

-- friends
import System.Network.ZMQ.MDP.Util

data Protocol = MDCP01

data Response = Response { protocol :: Protocol,
                           service :: ByteString,
                           response :: [ByteString] }


-- this can either be XReq or Req...
data ClientSocket = ClientSocket { clientSocket :: Socket Req }


data ClientError = ClientTimedOut
                 | ClientBadProtocol

withClientSocket :: String -> (ClientSocket -> IO a) -> IO a
withClientSocket socketAddress io =
 withContext 1 $ \c -> withSocket c Req $ \s -> do
   connect s socketAddress
   io (ClientSocket s)


sendAndReceive :: ClientSocket -> ByteString -> [ByteString] -> IO (Either ClientError Response)
sendAndReceive mdpcs svc msgs =
  do -- Z.send sock "" [SndMore]
     Z.send sock "MDPC01"  [SndMore]
     Z.send sock svc       [SndMore]
     sendAll sock msgs
     maybeprot <- timeout (1000000 * 3) $ receive sock []
     case maybeprot of
       Nothing -> return $ Left ClientTimedOut
       Just "MDPC01" -> do
         res <- Response MDCP01 <$> receive sock [] <*> receiveUntilEnd sock
         return $ Right res
       _ -> return $ Left ClientBadProtocol
  where
    sock = clientSocket mdpcs

