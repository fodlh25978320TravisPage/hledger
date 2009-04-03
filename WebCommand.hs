{-| 
A happs-based web UI for hledger.
-}

module WebCommand
where
import Control.Monad.Trans (liftIO)
import Data.ByteString.Lazy.UTF8 (toString)
import qualified Data.Map as M
import Data.Map ((!))
import Data.Time.Clock
import Data.Time.Format
import System.Locale
import Control.Concurrent
import qualified Data.ByteString.Lazy.Char8 as B
import Happstack.Data (defaultValue)
import Happstack.Server
import Happstack.Server.HTTP.FileServe (fileServe)
import Happstack.State.Control (waitForTermination)
import System.Cmd (system)
import System.Info (os)
import System.Exit

import Ledger
import Options
import BalanceCommand
import RegisterCommand
import PrintCommand


tcpport = 5000

web :: [Opt] -> [String] -> Ledger -> IO ()
web opts args l =
  if Debug `elem` opts
     then do
       putStrLn $ printf "starting web server on port %d in debug mode" tcpport
       simpleHTTP nullConf{port=tcpport} handlers
     else do
       putStrLn $ printf "starting web server on port %d" tcpport
       tid <- forkIO $ simpleHTTP nullConf{port=tcpport} handlers
       putStrLn "starting web browser"
       openBrowserOn $ printf "http://localhost:%s/balance" (show tcpport)
       waitForTermination
       putStrLn "shutting down web server..."
       killThread tid
       putStrLn "shutdown complete"

    where
      handlers :: ServerPartT IO Response
      handlers = msum
       [dir "print" $ withDataFn (look "a") $ \a -> templatise $ printreport [a]
       ,dir "print" $ templatise $ printreport []
       ,dir "register" $ withDataFn (look "a") $ \a -> templatise $ registerreport [a]
       ,dir "register" $ templatise $ registerreport []
       ,dir "balance" $ withDataFn (look "a") $ \a -> templatise $ balancereport [a]
       ,dir "balance" $ templatise $ balancereport []
       ]
      printreport apats    = showLedgerTransactions opts (apats ++ args) l
      registerreport apats = showRegisterReport opts (apats ++ args) l
      balancereport []  = showBalanceReport opts args l
      balancereport apats  = showBalanceReport opts (apats ++ args) l'
          where l' = cacheLedger apats (rawledger l) -- re-filter by account pattern each time

templatise :: String -> ServerPartT IO Response
templatise s = do
  r <- askRq
  return $ setHeader "Content-Type" "text/html" $ toResponse $ maintemplate r s

maintemplate :: Request -> String -> String
maintemplate r = printf (unlines
  ["<div style=float:right>"
  ,"<form action=%s>search:&nbsp;<input name=a value=%s></form>"
  ,"</div>"
  ,"<div align=center style=width:100%%>"
  ," <a href=balance>balance</a>"
  ,"|"
  ," <a href=register>register</a>"
  ,"|"
  ," <a href=print>print</a>"
  ,"</div>"
  ,"<pre>%s</pre>"
  ])
  (dropWhile (=='/') $ rqUri r)
  (fromMaybe "" $ queryValue "a" r)

queryValues :: String -> Request -> [String]
queryValues q r = map (B.unpack . inputValue . snd) $ filter ((==q).fst) $ rqInputs r

queryValue :: String -> Request -> Maybe String
queryValue q r = case filter ((==q).fst) $ rqInputs r of
                   [] -> Nothing
                   is -> Just $ B.unpack $ inputValue $ snd $ head is

-- | Attempt to open a web browser on the given url, all platforms.
openBrowserOn :: String -> IO ExitCode
openBrowserOn u = trybrowsers browsers u
    where
      trybrowsers (b:bs) u = do
        e <- system $ printf "%s %s" b u
        case e of
          ExitSuccess -> return ExitSuccess
          ExitFailure _ -> trybrowsers bs u
      trybrowsers [] u = do
        putStrLn $ printf "Sorry, I could not start a browser (tried: %s)" $ intercalate ", " browsers
        putStrLn $ printf "Please open your browser and visit %s" u
        return $ ExitFailure 127
      browsers | os=="darwin"  = ["open"]
               | os=="mingw32" = ["firefox","safari","opera","iexplore"]
               | otherwise     = ["sensible-browser","firefox"]
    -- jeffz: write a ffi binding for it using the Win32 package as a basis
    -- start by adding System/Win32/Shell.hsc and follow the style of any
    -- other module in that directory for types, headers, error handling and
    -- what not.
    -- ::ShellExecute(NULL, "open", "www.somepage.com", NULL, NULL, SW_SHOWNORMAL);
    -- ::ShellExecute(NULL, "open", "firefox.exe", "www.somepage.com" NULL, SW_SHOWNORMAL);

