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
data ClientSocket = ClientSocket { clientSocket :: Socket XReq }


data ClientError = ClientTimedOut
                 | ClientBadProtocol

withClientSocket :: String -> (ClientSocket -> IO a) -> IO a
withClientSocket socketAddress io = do
  outer <- withContext 1 $ \c -> do
    res <- withSocket c XReq $ \s -> do
      connect s socketAddress
      res <- io (ClientSocket s)
      return res
    return res
  return outer
  
-- pretty sure there's a nicer way of doing this...
-- retry :: Monad m => Int -> m (Maybe a) -> m (Maybe a)
retry :: (Eq a1, Num a1) => a1 -> IO (Maybe a) -> IO (Maybe a)
retry n_ action = go n_
  where go 0 = return Nothing
        go n = do
          -- Prelude.putStrLn "Retrying action"
          result <- action
          case result of
            Nothing -> go (n-1)
            Just x -> return $ Just x
    
sendAndReceive :: ClientSocket -> ByteString -> [ByteString] -> IO (Either ClientError Response)
sendAndReceive mdpcs svc msgs =
  do -- Z.send sock "" [SndMore]
     Z.send sock "MDPC01"  [SndMore]
     Z.send sock svc       [SndMore]
     sendAll sock msgs
     -- arguably we shouldn't retry if the protocol is bad.
     -- but i'm disinclined to make the code more complex to cope
     
     -- receive crashes hard when you try to timeout - but later, in zmq_term.
     -- very odd

     maybeprot <- retry 3 $ poll [S sock Z.In] (1000000 * 3) >>= pollExtract
     -- maybeprot <- retry 3 $ timeout (1000000 * 3) $ receive sock []
     case maybeprot of
       Nothing -> return $ Left ClientTimedOut
       Just "MDPC01" -> do
         res <- Response MDCP01 <$> receive sock [] <*> receiveUntilEnd sock
         return $ Right res
       _ -> return $ Left ClientBadProtocol
  where
    pollExtract [S s Z.In] = Just <$> receive s [] 
    pollExtract _ = return Nothing
    
    sock = clientSocket mdpcs

