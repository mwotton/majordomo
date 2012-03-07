{-# LANGUAGE OverloadedStrings #-}
module MDWorker where
import Data.ByteString.Char8
import Data.Int
import Prelude 
import qualified System.ZMQ as Z
import System.ZMQ hiding(receive)
import Control.Applicative
import Data.Maybe(maybeToList)
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
send_to_broker sock cmd option message = 
  send_all sock $ ["",
                   pack $ show WORKER_PROTOCOL,
                   pack $ show cmd] ++
                   maybeToList option ++
                   maybeToList message

whileJust :: Monad m => (b -> m (Maybe b)) -> b -> m b
whileJust action seed = action seed >>=  maybe (return seed) (whileJust action)

start :: WorkerState a -> IO ()
start worker = forever (withBroker readTillDrop worker)

readTillDrop sock worker = whileJust (receive sock) worker


data WorkerState a = WorkerState { heartbeat_at :: UTCTime,
                                   liveness     :: Int,
                                   heartbeat    :: Int64,
                                   reconnect    :: Int,
                                   broker       :: String,
                                   context      :: System.ZMQ.Context,
                                   svc          :: ByteString,
                                   handler      :: ByteString -> IO ByteString
                                 }

epoch :: UTCTime
epoch = buildTime defaultTimeLocale []

lIVENESS = 3

defaultWorker = WorkerState { liveness = 1, -- start it ready to die.
                              heartbeat_at = epoch,
                              heartbeat = 2,
                              reconnect = 2
                            }


withBroker go worker =
  withSocket (context worker) XReq $ \sock -> do
    loggedPut ( "connecting to broker " ++ broker worker)
    connect sock (broker worker)
    send_to_broker sock READY (Just $ svc worker) Nothing
    now <- getCurrentTime
    let time = addUTCTime (fromIntegral $ heartbeat worker) now
    loggedPut ("beat at:" ++ show time)
    go sock worker { liveness     = lIVENESS,
                     heartbeat_at = time
                   }

loggedPut :: String -> IO ()
loggedPut res = do
  Prelude.putStr . show =<< getCurrentTime
  Prelude.putStrLn (": " ++ res)
  
receive sock worker = do loggedPut "polling"
                         next <- getMessage
                         case next of
                           Nothing -> loggedPut "no message" >> return Nothing
                           Just w -> loggedPut "message!" >> postCheck w
  where

  getMessage = do
    -- this timeout is different in 3.1
    loggedPut $ "Polling socket: should finish in " ++ (show (heartbeat worker)) ++ "seconds"
    
  --  [S _ polled] <- poll [S sock In] $ 1000000 * heartbeat worker
    polled <- timeout (1000000 * fromIntegral (heartbeat worker)) $ Z.receive sock []
    loggedPut "polled"
    case polled of
      Nothing -> noMessage
      Just s   -> handleEvent s
  
  noMessage :: IO (Maybe (WorkerState b))
  noMessage = do
    let live = liveness worker - 1
    if liveness worker == 0
       then loggedPut "reconnecting" >> threadDelay (1000000 * reconnect worker) >> return Nothing
       else return $ Just worker { liveness = live }
  postCheck :: WorkerState a -> IO (Maybe (WorkerState a))
  postCheck worker = do
      loggedPut "postcheck"
      time <- getCurrentTime
      loggedPut $ "beat at " ++ show (heartbeat_at worker)
      if time > heartbeat_at worker
        then do loggedPut "sending heartbeat"
                send_to_broker sock WORKER_HEARTBEAT Nothing Nothing
                loggedPut "sent heartbeat!"
                time <- getCurrentTime
                return $ Just $ worker { heartbeat_at = addUTCTime (fromIntegral $ heartbeat worker) time}
        else loggedPut "no heartbeat required" >> return (Just worker)
  handleEvent header = do
      let zrecv = Z.receive sock []
      loggedPut "handling"
      assert (header == "") (return ())
      prot <- zrecv
      assert (prot == "MDPW01") (return ())
      -- ideally, we'd encapsulate the process of reading
      -- the whole thing in in the parser. this will do for now though.
      command <- parseCommand <$> zrecv
      let new_worker = worker { liveness = lIVENESS }
      case command of
        Just REQUEST -> do
          loggedPut "handling a request"
          msg <- zrecv
          reply <- (handler worker) msg
          send_to_broker sock REPLY Nothing (Just reply)
          return $ Just new_worker
        Just HEARTBEAT -> do 
          loggedPut "handling a heartbeat"
          return $ Just new_worker
        Just DISCONNECT -> do
          loggedPut "handling a disconnect"
          return Nothing
        Nothing -> error "borked"
