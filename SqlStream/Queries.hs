module SqlStream.Queries where

import SqlStream.SqlStream
import qualified SqlStream.RMCStream as RMCStream
import Doc
import qualified Utils
import qualified Logger
import Conf

import qualified RMC.Protobuf.RMC.RMC	as RMC
import qualified RMC.API 		as RMC
import qualified Text.ProtocolBuffers.WireMessage as Protobuf

import System.ZMQ as ZMQ

import Control.Monad
import qualified Data.ByteString.Char8 as BSC8
import qualified Data.List as List

import qualified Data.Map {- remove it -}

queries :: [Query ()]
queries = [query1, query2, query3]

-- number of message to receive
maxMess = 1000

inQueriesRangeAssert :: Int -> IO ()
inQueriesRangeAssert x = if x < length queries && x >= 0
                         then return ()
                         else Utils.exitWithErr "SqlSrv: no such query"

--------------------------------------------------------------------------------
-- queries
query1 :: Query ()
query1 = do 
  select $ ["time", "Count time", "Sum speed"]

  from $ RMCStream.rmcTableMeta

query2 :: Query ()
query2 = do 
  select $ ["direction"]

  from $ RMCStream.rmcTableMeta

  selectWhere [(\ str2Field -> 
                    str2Field "direction" > 180)]

-- TODOIT!
query3 :: Query ()
query3 = do 
  select $ ["time", "direction", "Truncate direction", "Count direction"]

  from $ RMCStream.rmcTableMeta

  selectWhere [(\ str2Field -> 
                    str2Field "direction" > 180)]

  groupBy ["direction"]

  having [(\ str2Field -> 
               (str2Field "Count direction") == 1)]

  orderBy [("time", ASC)]

--------------------------------------------------------------------------------

accum :: Acc -> Row -> Acc
accum = mkAccum query1

rmcs = []

result :: [Row]
result = extractAccum query1 folded where
    rows = map RMCStream.rmcToRow rmcs
    folded = foldl accum emptyAcc rows

--------------------------------------------------------------------------------

strToTime :: String -> Field
strToTime = const time
    where time = FDayTime $ Just $ read "2010-12-10 19:21:55.810178 UTC"

--------------------------------------------------------------------------------


main :: [String] -> IO ()
main args = do 
  Doc.helpInArgsCheck args Doc.sqlSrvUsage
  Doc.lengthArgsAssert (length args > 1)
  Doc.naturalNumAssert (args !! 0) "SqlSrv error: 1st argument must be integer"
  Doc.naturalNumAssert (args !! 1) "SqlSrv error: 2nd argument must be integer"
  inQueriesRangeAssert $ read $ args !! 0

  let queryIdx :: Int
      queryIdx  = read $ args !! 0
      query	= queries !! queryIdx
      agregIdx	= read $ args !! 1

  connectTo 	<- liftM (map nodeOutput) $ Conf.getParsers
  toBindO	<- liftM nodeOutput 	  $ Conf.getNAgreg agregIdx

  context <- ZMQ.init 1

  {- making input connection -}
  iSock <- socket context Sub
  subscribe iSock ""
  forM_ connectTo $ \ parserAddr -> do
      connect iSock parserAddr

  {- making output connection -}
  oSock <- socket context Pub
  bind oSock toBindO

  putStrLn $ "serving {" ++ List.intercalate ", " connectTo ++ 
             "} with query " ++ show queryIdx
  rows <- liftM concat $ replicateM maxMess $ do
              rmc <- receive iSock []
              case Protobuf.messageGet (Utils.toLazyBS rmc) of
                (Left err)  	    -> do Logger.messageGetError rmc err
                                          return []
                -- do send oSock (Utils.fromLazyBS $ Protobuf.messagePut rmc) []
                (Right (rmc, rest)) -> return [RMCStream.rmcToRow rmc]

  let acc 	= List.foldl' (mkAccum query) emptyAcc rows
      result	= extractAccum query acc
      tableMeta = qOutputTable query
      msg 	= BSC8.pack $ show (tableMeta, result)

  -- debug info
  putStrLn $ "sending " ++ show tableMeta ++ "\n" ++ List.intercalate "\n" (map show result)
  putStrLn $ "rows                      : " ++ show (length rows)
  putStrLn $ "rows in map(groups count) : " ++ show (length $ map snd $ Data.Map.toList acc)
  putStrLn $ "rows in map(in fst group) : " ++ show (length $ head $ map snd $ Data.Map.toList acc)
  putStrLn $ "rows in msg               : " ++ show (length $ result)
  send oSock msg []

  ZMQ.close oSock
  ZMQ.close iSock
  ZMQ.term context
  return ()
