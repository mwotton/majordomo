{-# LANGUAGE OverloadedStrings #-}
module System.Network.ZMQ.MDP.Worker where
import Data.ByteString.Char8
import Data.Int
import Prelude hiding (putStr, putStrLn)
import qualified Prelude
import qualified System.ZMQ as Z
import System.ZMQ hiding(receive)
import Control.Applicative

import Control.Exception
import Control.Monad
import Data.Time.Clock
import Data.Time.Format
import System.Locale
import Control.Concurrent
import System.Timeout

data Protocol = WORKER_PROTOCOL
instance Show Protocol where
  show WORKER_PROTOCOL = "MDPW01"

type Address = ByteString -- cheaty.

data Response = Response { envelope :: ! [Address],
                           body     :: ! [ByteString] }

data ResponseCode = REPLY | READY | WORKER_HEARTBEAT
instance Show ResponseCode where
  show REPLY      = "\003"
  show READY      = "\001"
  show WORKER_HEARTBEAT  = "\004"

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

   
read_till_empty :: Socket a -> IO [ByteString]
read_till_empty sock = do
  frame <- Z.receive sock []
  if frame == ""
     then return []
     else (frame:) <$> read_till_empty sock


send_all :: Socket a -> [ByteString] -> IO ()
send_all sock = go
  where go [l] = Z.send sock l []
        go (x:xs) =  Z.send sock x [SndMore] >> go xs
        go []     = error "empty send not allowed"


send_to_broker :: Socket a -> ResponseCode -> [ByteString] ->
                  [ByteString] -> IO ()
send_to_broker sock cmd option message =
  send_all sock $ ["",
                   pack $ show WORKER_PROTOCOL,
                   pack $ show cmd] ++ option ++ message

{-
Frame 0: Empty frame
Frame 1: "MDPW01" (six bytes, representing MDP/Worker v0.1)
Frame 2: 0x03 (one byte, representing REPLY)
Frame 3: Client address (envelope stack)
Frame 4: Empty (zero bytes, envelope delimiter)
Frames 5+: Reply body (opaque binary)
-}

-- FIXME might we ever want to send a multi-part body?
--
send_response :: Socket a -> Response -> IO ()
send_response sock resp = send_to_broker sock REPLY (envelope resp) (body resp)

--  send_to_broker sock REPLY Nothing [reply])

whileJust :: Monad m => (b -> m (Maybe b)) -> b -> m b
whileJust action seed = action seed >>=  maybe (return seed) (whileJust action)

start :: WorkerState a -> IO ()
start worker = forever (withBroker readTillDrop worker)

readTillDrop :: Socket a -> WorkerState a1 -> IO (WorkerState a1)
readTillDrop sock worker = whileJust (receive sock) worker


data WorkerState a = WorkerState { heartbeat_at :: ! UTCTime,
                                   liveness     :: ! Int,
                                   heartbeat    :: ! Int64,
                                   reconnect    :: ! Int,
                                   broker       :: String,
                                   context      :: System.ZMQ.Context,
                                   svc          :: ByteString,
                                   handler      :: ByteString -> IO ByteString
                                 }

epoch :: UTCTime
epoch = buildTime defaultTimeLocale []

lIVENESS :: Int
lIVENESS = 3


withWorker :: String -> ByteString -> (ByteString -> IO ByteString) -> IO ()
withWorker  broker_ service_ io =
 withContext 1 $ \c -> 
 start WorkerState { broker = broker_,
                     context = c,
                     svc = service_,
                     handler = io,
                     liveness = 1,
                     heartbeat_at = epoch,
                     heartbeat = 2,
                     reconnect = 2
                   }
 


withBroker :: (Socket XReq -> WorkerState a -> IO b) -> WorkerState t -> IO b
withBroker go worker =
  withSocket (context worker) XReq $ \sock -> do
    loggedPut ( "connecting to broker " ++ broker worker)
    connect sock (broker worker)
    send_to_broker sock READY [svc worker] []
    now <- getCurrentTime
    let time = addUTCTime (fromIntegral $ heartbeat worker) now
    loggedPut ("beat at:" ++ show time)
    go sock worker { liveness     = lIVENESS,
                     heartbeat_at = time
                   }

loggedPut :: String -> IO ()
loggedPut _res = return () -- do
--  Prelude.putStr . show =<< getCurrentTime
--  Prelude.putStrLn (": " ++ res)

receive :: Socket a -> WorkerState a1 -> IO (Maybe (WorkerState a2))
receive sock worker = do loggedPut "polling"
                         next <- getMessage
                         case next of
                           Nothing -> loggedPut "no message" >> return Nothing
                           Just w -> loggedPut "message!" >> postCheck w
  where

  getMessage = do
    -- this timeout is different in 3.1
    -- loggedPut $ "Polling socket: should finish in " ++ (show (heartbeat worker)) ++ "seconds"

    [S _ polled] <- poll [S sock In] $ 1000000 * heartbeat worker
    -- use this in 3.1
    -- polled <- timeout (1000000 * fromIntegral (heartbeat worker)) $ Z.receive sock []

    case polled of
      None -> noMessage
      In   -> Z.receive sock [] >>= handleEvent
    -- case polled of
    --   Nothing -> noMessage
    --   Just s   -> handleEvent s

  noMessage :: IO (Maybe (WorkerState b))
  noMessage = do
    let live = liveness worker - 1
    if liveness worker == 0
       then loggedPut "reconnecting" >> threadDelay (1000000 * reconnect worker) >> return Nothing
       else return $ Just worker { liveness = live }
  postCheck :: WorkerState a -> IO (Maybe (WorkerState a))
  postCheck worker = do
      --loggedPut "postcheck"
      time <- {-# SCC "getCurrentTime" #-} getCurrentTime
      -- loggedPut $ "beat at " ++ show (heartbeat_at worker)
      if {-# SCC "time_comparison" #-} time > heartbeat_at worker
        then do --loggedPut "sending heartbeat"
                {-# SCC "postcheck_send" #-} send_to_broker sock WORKER_HEARTBEAT [] []
                --loggedPut "sent heartbeat!"
                {-# SCC "postcheck_return" #-} return $ Just $ updateWorkerTime worker time
        else return $ Just worker

  updateWorkerTime w time =
    w { heartbeat_at = {-# SCC "addtime" #-} addUTCTime (fromIntegral $! heartbeat w) time}

  handleEvent header = do
      let zrecv = Z.receive sock []
      -- loggedPut "handling"
      assert (header == "") (return ())
      prot <- zrecv
      assert (prot == "MDPW01") (return ())
      -- ideally, we'd encapsulate the process of reading
      -- the whole thing in in the parser. this will do for now though.
      command <- parseCommand <$> zrecv
      let new_worker = worker { liveness = lIVENESS }
      case command of
        Just REQUEST -> do
          addresses <- read_till_empty sock
          msg <- zrecv
          reply_string <- (handler worker) msg
          send_response sock Response { envelope = addresses,
                                        body = [reply_string] }
          return $ Just new_worker
        Just HEARTBEAT -> do
          -- loggedPut "handling a heartbeat"
          return $ Just new_worker
        Just DISCONNECT -> do
          -- loggedPut "handling a disconnect"
          return Nothing
        Nothing -> error "borked"

