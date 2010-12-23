module FrontEndApp where

import System.ZMQ as ZMQ

import qualified Data.ByteString.Char8 as BSC8
import Control.Monad

import qualified Utils(maybeRead)
import qualified Conf
import qualified Doc
import qualified Logger
import SqlStream.SqlStream

file = "result.html"

mkHtml :: TableMeta -> [Row] -> String
mkHtml = undefined

main :: [String] -> IO ()
main args = do 
  Doc.helpInArgsCheck args Doc.frontEndUsage

  parsers <- liftM (map Conf.nodeOutput) $ Conf.getParsers

  context <- ZMQ.init 1

  -- binding input socket
  iSock <- socket context Sub
  forM parsers $ \ parser -> do
    connect iSock parser

  putStrLn $ "receiving query result ..."
  forever $ do
    msg <- receive iSock []
    case Utils.maybeRead $ BSC8.unpack msg of
      Nothing		-> Logger.resultReadError msg
      (Just (tm, res))	-> appendFile file $ mkHtml tm res