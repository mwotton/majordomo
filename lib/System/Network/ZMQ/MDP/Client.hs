{-# LANGUAGE OverloadedStrings #-}
module System.Network.ZMQ.MDP.Client where
import Data.ByteString.Char8
import qualified System.ZMQ as Z
import System.ZMQ hiding(send)
import Control.Applicative
import System.Timeout

data Protocol = MDCP01

data Response = Response { protocol :: Protocol,
                           service :: ByteString,
                           response :: [ByteString] }


receiveTillEmpty :: Socket a -> IO [ByteString]
receiveTillEmpty sock = do
  more <- Z.moreToReceive sock
  if more  
    then (:) <$> receive sock [] <*> receiveTillEmpty sock
    else return []


send :: Socket a -> ByteString -> ByteString -> IO (Either ByteString Response)
send sock svc input =
  do Z.send sock "MDPC01"  [SndMore]
     Z.send sock svc [SndMore]
     Z.send sock input  []
     maybeprot <- timeout (1000000 * 3) $ receive sock []
     case maybeprot of
       Nothing -> return $ Left "Timed out!"
       Just "MDPC01" -> do
         res <- Response MDCP01 <$> receive sock [] <*> receiveTillEmpty sock
         return $ Right res
       _ -> return $ Left "bad protocol"
