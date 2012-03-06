{-# LANGUAGE OverloadedStrings #-}
module MDWorker where
import Data.ByteString.Char8
import Prelude hiding(putStrLn)
import qualified System.ZMQ as Z
import System.ZMQ hiding(receive)
import Control.Applicative
import Data.Maybe(maybeToList)
import Control.Exception
import Control.Monad
import Control.Monad.Loops(iterateWhile)

data Protocol = WORKER_PROTOCOL
instance Show Protocol where
  show WORKER_PROTOCOL = "MDPW01"

data Response = Response { protocol :: Protocol,
                           service :: ByteString,
                           response :: ByteString }



data ResponseCode = REPLY | READY
instance Show ResponseCode where
  show REPLY      = "\003"

  show READY      = "\001"
data CommandCode = REQUEST | HEARTBEAT | DISCONNECT
instance Show CommandCode where
  show REQUEST    = "\002"
  show HEARTBEAT  = "\004"
  show DISCONNECT = "\005"

parseCommand ::  ByteString -> Maybe CommandCode
parseCommand "\002" = Just REQUEST
parseCommand "\004" = Just HEARTBEAT
parseCommand "\005" = Just DISCONNECT
parseCommand _ = Nothing
                

type MDError = ByteString                              

send_all :: Socket a -> [ByteString] -> IO ()
send_all sock [l] = Z.send sock l []
send_all sock (x:xs) =   Z.send sock x [SndMore] >> send_all sock xs
send_all _ [] = error "empty send not allowed"


send_to_broker :: Socket a -> ResponseCode -> Maybe ByteString -> Maybe ByteString -> IO ()
send_to_broker sock cmd option message = do
  send_all sock $ ["",
                   pack $ show WORKER_PROTOCOL, 
                   pack $ show cmd] ++ 
                   maybeToList option ++ 
                   maybeToList message


  -- Z.send sock "\001" [SndMore]
  -- Z.send sock servicename []  
  

broker_connect :: Socket a -> ByteString -> IO ()
broker_connect sock servicename =   send_to_broker sock READY (Just servicename) Nothing


start :: Socket a -> ByteString -> (ByteString -> IO ( ByteString)) -> IO b
start sock servicename handler  = do 
  putStrLn "worker starting" 
  forever $ do
    broker_connect sock servicename
    iterateWhile id $ receive sock handler
  



receive :: Socket a -> (ByteString -> IO  ByteString) -> IO Bool
receive sock handler = go $ WorkerState { time :: UTCTime,

  where
    go
     putStrLn "receiving"
     header <- Z.receive sock []
     assert (header == "") (return ())
     prot <- Z.receive sock []
     assert (prot == "MDPW01") (return ())
     -- ideally, we'd encapsulate the process of reading
     -- the whole thing in in the parser. this will do for now though.
     command <- parseCommand <$> Z.receive sock []
     case command of
       Just REQUEST -> do
         msg <- Z.receive sock []
         reply <- handler msg
         send_to_broker sock REPLY Nothing (Just reply)
         return True
       Just HEARTBEAT ->  return True
       Just DISCONNECT -> return False
       Nothing -> error "borked"
       
       --         in_msg <-  Z.receive sock []
       --         out_msg <- handler in_msg
       --         print [_seqid, in_msg, out_msg]
       --         send_to_broker sock 
       --         Z.send sock "MDPW01"  [SndMore]
       --         Z.send sock servicename  [SndMore]
       --         Z.send sock out_msg  []
       -- else putStrLn $"bad protocol|" `append` prot `append` "|"
                         
     