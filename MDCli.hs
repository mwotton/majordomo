{-# LANGUAGE OverloadedStrings #-}
module MDCli where
import Data.ByteString.Char8
import qualified System.ZMQ as Z
import System.ZMQ hiding(send)
import Control.Applicative

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
     prot <- receive sock []
     if prot == "MDPC01"
       then  Right <$> (Response MDCP01 <$> receive sock [] <*> receive sock [])
       else return (Left prot)
                            
                         
     