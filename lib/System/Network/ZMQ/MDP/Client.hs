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
                           response :: ByteString }
                
type MDError = ByteString                              


send :: Socket a -> ByteString -> IO (Either ByteString Response)
send sock input =
  do connect sock "tcp://*:5555" 
     Z.send sock "MDPC01"  [SndMore]
     Z.send sock "echo" [SndMore]
     Z.send sock input  []
     maybeprot <- timeout (1000000 * 3) $ receive sock []
     case maybeprot of
       Nothing -> return $ Left "Timed out!"
       Just "MDPC01" -> do
         res <- Response MDCP01 <$> receive sock [] <*> receive sock []
         return $ Right res
       _ -> return $ Left "bad protocol"
                            
                         
     