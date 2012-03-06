{-# LANGUAGE OverloadedStrings #-}
module MDWorker where
import Data.ByteString.Char8
import Data.Int
import Prelude hiding(putStrLn)
import qualified System.ZMQ as Z
import System.ZMQ hiding(receive)
import Control.Applicative
import Data.Maybe(maybeToList)
import Control.Exception
import Control.Monad
import Control.Monad.Loops(iterateWhile)
import Data.Time.Clock
import Data.Time.Format
import System.Locale
import Control.Concurrent

data Protocol = WORKER_PROTOCOL
instance Show Protocol where
  show WORKER_PROTOCOL = "MDPW01"

data Response = Response { protocol :: Protocol,
                           service :: ByteString,
                           response :: ByteString }



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

send_all :: Socket a -> [ByteString] -> IO ()
send_all sock [l] = Z.send sock l []
send_all sock (x:xs) =   Z.send sock x [SndMore] >> send_all sock xs
send_all _ [] = error "empty send not allowed"


send_to_broker :: Socket a -> ResponseCode -> Maybe ByteString ->
                  Maybe ByteString -> IO ()
send_to_broker sock cmd option message = do
  send_all sock $ ["",
                   pack $ show WORKER_PROTOCOL,
                   pack $ show cmd] ++
                   maybeToList option ++
                   maybeToList message

broker_connect :: Socket a -> ByteString -> IO ()
broker_connect sock svc = send_to_broker sock READY (Just svc) Nothing

whileJust :: Monad m => (b -> m (Maybe b)) -> b -> m b
whileJust action seed = action seed >>=  maybe (return seed) (whileJust action)

start :: Socket a -> ByteString -> (ByteString -> IO ( ByteString)) -> IO b
start sock servicename req_handler  = do
  putStrLn "worker starting"
  time <- addUTCTime (fromIntegral $ heartbeat defaultWorker) <$> getCurrentTime
  let worker = defaultWorker { heartbeat_at = time, handler = req_handler }
  forever $ do
    broker_connect sock servicename
    whileJust (receive sock) worker

data WorkerState = WorkerState { heartbeat_at :: UTCTime,
                                 liveness     :: Int,
                                 heartbeat    :: Int64,
                                 reconnect    :: Int,
                                 handler      :: ByteString -> IO ByteString
                               }

epoch :: UTCTime
epoch = buildTime defaultTimeLocale []

defaultWorker :: WorkerState
defaultWorker = WorkerState { liveness = 3,
                              heartbeat_at = epoch,
                              heartbeat = fromIntegral 3000,
                              reconnect = 3000
                            }

receive :: Socket a -> WorkerState -> IO (Maybe WorkerState)
receive sock worker = do
  [S _ polled] <- poll [S sock In] $ heartbeat worker
  case polled of
    None -> postCheck
    In   -> handleEvent
    _    -> error "oops, fucked"
  where
    postCheck = do
      let newWorker = worker { liveness = liveness worker - 1 }
      if liveness newWorker == 0
        then do
          send_to_broker sock WORKER_HEARTBEAT Nothing Nothing
          time <- getCurrentTime
          return $ Just $ newWorker { heartbeat_at = addUTCTime (fromIntegral $ heartbeat worker) time}
        else threadDelay (reconnect newWorker) >> return Nothing

    handleEvent = do
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
          reply <- (handler worker) msg
          send_to_broker sock REPLY Nothing (Just reply)
          return $ Just worker
        Just HEARTBEAT ->  return $ Just worker
        Just DISCONNECT -> return Nothing
        Nothing -> error "borked"
