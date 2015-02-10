{-# LANGUAGE TemplateHaskell, ScopedTypeVariables #-}

import Codeec.Shim
import Codeec.ClientMonad
import Codeec.Marshall
import Codeec.NameService.Types
import Codeec.NameService.SimpleBroker
import Codeec.TH

import System.Process (runCommand, terminateProcess)
import System.Environment (getExecutablePath, getArgs)
import Database.Cassandra.CQL
import Control.Monad.Trans (liftIO)
import Data.Text (pack)
import Codeec.Types (summarize)
import Control.Monad (replicateM_)
import Control.Concurrent (threadDelay)

import MicroBlogDefs
import MicroBlogCtrts
import MicroBlogTxns

fePort :: Int
fePort = 5558

bePort :: Int
bePort = 5559


data Kind = B | C | S | D | Drop deriving (Read, Show)

keyspace :: Keyspace
keyspace = Keyspace $ pack "MicroBlog"

dtLib = mkDtLib [(AddUser, mkGenOp addUser summarize, $(checkOp AddUser addUserCtrt)),
                 (AddUsername, mkGenOp addUsername summarize, $(checkOp AddUsername addUsernameCtrt)),
                 (GetUserID, mkGenOp getUserID summarize, $(checkOp GetUserID getUserIDCtrt)),
                 (GetUserInfo, mkGenOp getUserInfo summarize, $(checkOp GetUserInfo getUserInfoCtrt)),
                 (AddFollower, mkGenOp addFollower summarize, $(checkOp AddFollower addFollowerCtrt)),
                 (RemFollower, mkGenOp remFollower summarize, $(checkOp RemFollower remFollowerCtrt)),
                 (AddFollowing, mkGenOp addFollowing summarize, $(checkOp AddFollowing addFollowingCtrt)),
                 (RemFollowing, mkGenOp remFollowing summarize, $(checkOp RemFollowing remFollowingCtrt)),
                 (Blocks, mkGenOp addBlocks summarize, $(checkOp Blocks addBlocksCtrt)),
                 (IsBlockedBy, mkGenOp addIsBlockedBy summarize, $(checkOp IsBlockedBy addIsBlockedByCtrt)),
                 (GetBlocks, mkGenOp getBlocks summarize, $(checkOp GetBlocks getBlocksCtrt)),
                 (GetIsBlockedBy, mkGenOp getIsBlockedBy summarize, $(checkOp GetIsBlockedBy getIsBlockedByCtrt)),
                 (GetFollowers, mkGenOp getFollowers summarize, $(checkOp GetFollowers getFollowersCtrt)),
                 (GetFollowing, mkGenOp getFollowing summarize, $(checkOp GetFollowing getFollowingCtrt)),
                 (NewTweet, mkGenOp addTweet summarize, $(checkOp NewTweet addTweetCtrt)),
                 (GetTweet, mkGenOp getTweet summarize, $(checkOp GetTweet getTweetCtrt)),
                 (NewTweetTL, mkGenOp addToTimeline summarize, $(checkOp NewTweetTL addToTimelineCtrt)),
                 (GetTweetsInTL, mkGenOp getTweetsInTimeline summarize, $(checkOp GetTweetsInTL getTweetsInTimelineCtrt)),
                 (NewTweetUL, mkGenOp addToUserline summarize, $(checkOp NewTweetUL addToUserlineCtrt)),
                 (GetTweetsInUL, mkGenOp getTweetsInUserline summarize, $(checkOp GetTweetsInUL getTweetsInUserlineCtrt))]

main :: IO ()
main = do
  (kindStr:broker:restArgs) <- getArgs
  let k :: Kind = read kindStr
  let ns = mkNameService (Frontend $ "tcp://" ++ broker ++ ":" ++ show fePort)
                         (Backend  $ "tcp://" ++ broker ++ ":" ++ show bePort) "localhost" 5560
  case k of
    B -> startBroker (Frontend $ "tcp://*:" ++ show fePort)
                     (Backend $ "tcp://*:" ++ show bePort)

    S -> do
      runShimNode dtLib [("localhost","9042")] keyspace ns

    C -> runSession ns $ do
      key <- liftIO $ newKey
      r::() <- invoke key AddUser ("Alice","test123")
      return ()

    D -> do
      pool <- newPool [("localhost","9042")] keyspace Nothing
      runCas pool $ createTables
      progName <- getExecutablePath
      putStrLn "Driver : Starting broker"
      b <- runCommand $ progName ++ " B"
      putStrLn "Driver : Starting server"
      s <- runCommand $ progName ++ " S"
      putStrLn "Driver : Starting client"
      c <- runCommand $ progName ++ " C"
      threadDelay 25000000
      mapM_ terminateProcess [b,s,c]
      runCas pool $ dropTables

    Drop -> do
      pool <- newPool [("localhost", "9042")] keyspace Nothing
      runCas pool $ dropTables