{-# LANGUAGE CPP, TypeFamilies, QuasiQuotes, TemplateHaskell #-}
{-| 
A web-based UI.
-}

module Hledger.Cli.Commands.Web
where
import Control.Concurrent (forkIO, threadDelay)
import Control.Applicative ((<$>), (<*>))
import Data.Either
import System.FilePath ((</>))
import System.IO.Storage (withStore, putValue, getValue)
import Text.ParserCombinators.Parsec (parse)
import Yesod

import Hledger.Cli.Commands.Add (journalAddTransaction)
import Hledger.Cli.Commands.Balance
import Hledger.Cli.Commands.Print
import Hledger.Cli.Commands.Register
import Hledger.Cli.Options hiding (value)
import Hledger.Cli.Utils
import Hledger.Data
import Hledger.Read (journalFromPathAndString)
import Hledger.Read.Journal (someamount)
#ifdef MAKE
import Paths_hledger_make (getDataFileName)
#else
import Paths_hledger (getDataFileName)
#endif


defhost = "localhost"
defport = 5000
defbaseurl = printf "http://%s:%d" defhost defport :: String
browserstartdelay = 100000 -- microseconds
hledgerurl = "http://hledger.org"
manualurl = hledgerurl++"/MANUAL.html"

web :: [Opt] -> [String] -> Journal -> IO ()
web opts args j = do
  let baseurl = fromMaybe defbaseurl $ baseUrlFromOpts opts
      port = fromMaybe defport $ portFromOpts opts
  unless (Debug `elem` opts) $ forkIO (browser baseurl) >> return ()
  server baseurl port opts args j

browser :: String -> IO ()
browser baseurl = do
  putStrLn "starting web browser"
  threadDelay browserstartdelay
  openBrowserOn baseurl
  return ()

server :: String -> Int -> [Opt] -> [String] -> Journal -> IO ()
server baseurl port opts args j = do
    printf "starting web server on port %d with base url %s\n" port baseurl
    fp <- getDataFileName "web"
    let app = HledgerWebApp{
               appOpts=opts
              ,appArgs=args
              ,appJournal=j
              ,appWebdir=fp
              ,appRoot=baseurl
              }
    withStore "hledger" $ do
     putValue "hledger" "journal" j
     basicHandler port app

data HledgerWebApp = HledgerWebApp {
      appOpts::[Opt]
     ,appArgs::[String]
     ,appJournal::Journal
     ,appWebdir::FilePath
     ,appRoot::String
     }

mkYesod "HledgerWebApp" [$parseRoutes|
/             IndexPage        GET
/style.css    StyleCss         GET
/journal      JournalPage      GET POST
/edit         EditPage         GET POST
/register     RegisterPage     GET
/balance      BalancePage      GET
|]

instance Yesod HledgerWebApp where approot = appRoot

getIndexPage :: Handler HledgerWebApp ()
getIndexPage = redirect RedirectTemporary JournalPage

getStyleCss :: Handler HledgerWebApp ()
getStyleCss = do
    app <- getYesod
    let dir = appWebdir app
    sendFile "text/css" $ dir </> "style.css"

getJournalPage :: Handler HledgerWebApp RepHtml
getJournalPage = withLatestJournalRender (const showTransactions)

getRegisterPage :: Handler HledgerWebApp RepHtml
getRegisterPage = withLatestJournalRender showRegisterReport

getBalancePage :: Handler HledgerWebApp RepHtml
getBalancePage = withLatestJournalRender render
    where render opts filterspec j = showBalanceReport opts $ balanceReport opts filterspec j

withLatestJournalRender :: ([Opt] -> FilterSpec -> Journal -> String) -> Handler HledgerWebApp RepHtml
withLatestJournalRender reportfn = do
    app <- getYesod
    t <- liftIO $ getCurrentLocalTime
    a <- fromMaybe "" <$> lookupGetParam "a"
    p <- fromMaybe "" <$> lookupGetParam "p"
    let opts = appOpts app ++ [Period p]
        args = appArgs app ++ [a]
        fspec = optsToFilterSpec opts args t
    -- reload journal if changed, displaying any error as a message
    j <- liftIO $ fromJust `fmap` getValue "hledger" "journal"
    (jE, changed) <- liftIO $ journalReloadIfChanged opts j
    let (j', err) = either (\e -> (j,e)) (\j -> (j,"")) jE
    when (changed && null err) $ liftIO $ putValue "hledger" "journal" j'
    if (changed && not (null err)) then setMessage $ string "error while reading"
                                 else return ()
    -- run the specified report using this request's params
    let s = reportfn opts fspec j'
    -- render the standard template
    msg' <- getMessage
    -- XXX work around a bug, can't get the message we set above
    let msg = if null err then msg' else Just $ string $ printf "Error while reading %s" (filepath j')
    Just here <- getCurrentRoute
    hamletToRepHtml $ template here msg a p "hledger" s

template :: HledgerWebAppRoute -> Maybe (Html ()) -> String -> String
         -> String -> String -> Hamlet HledgerWebAppRoute
template here msg a p title content = [$hamlet|
!!!
%html
 %head
  %title $string.title$
  %meta!http-equiv=Content-Type!content=$string.metacontent$
  %link!rel=stylesheet!type=text/css!href=@stylesheet@!media=all
 %body
  ^navbar'^
  #messages $m$
  ^addform'^
  #content
   %pre $string.content$
|]
 where m = fromMaybe (string "") msg
       navbar' = navbar here a p
       addform' | here == JournalPage = addform
                | otherwise = nulltemplate
       stylesheet = StyleCss
       metacontent = "text/html; charset=utf-8"

nulltemplate = [$hamlet||]

navbar :: HledgerWebAppRoute -> String -> String -> Hamlet HledgerWebAppRoute
navbar here a p = [$hamlet|
 #navbar
  %a.toprightlink!href=$string.hledgerurl$ hledger.org
  \ $
  %a.toprightlink!href=$string.manualurl$ manual
  \ $
  ^navlinks'^
  ^searchform'^
|]
 where navlinks' = navlinks here a p
       searchform' = searchform here a p

navlinks :: HledgerWebAppRoute -> String -> String -> Hamlet HledgerWebAppRoute
navlinks here a p = [$hamlet|
 #navlinks
  ^journallink^ $
  (^editlink^) $
  | ^registerlink^ $
  | ^balancelink^ $
|]
 where
  journallink = navlink here "journal" JournalPage
  editlink = navlink here "edit" EditPage
  registerlink = navlink here "register" RegisterPage
  balancelink = navlink here "balance" BalancePage
  navlink here s dest = [$hamlet|%a.$style$!href=@?u@ $string.s$|]
   where u = (dest, concat [(if null a then [] else [("a", a)])
                           ,(if null p then [] else [("p", p)])])
         style | here == dest = string "navlinkcurrent"
               | otherwise = string "navlink"

searchform :: HledgerWebAppRoute -> String -> String -> Hamlet HledgerWebAppRoute
searchform here a p = [$hamlet|
 %form#searchform!method=GET
  filter by: $
  %input!name=a!size=20!value=$string.a$
  ^ahelp^ $
  in period: $
  %input!name=p!size=20!value=$string.p$
  ^phelp^ $
  %input!type=submit!value=filter
  ^resetlink^
|]
 where
  ahelp = helplink "filter-patterns" "?"
  phelp = helplink "period-expressions" "?"
  resetlink
   | null a && null p = nulltemplate
   | otherwise        = [$hamlet|%span#resetlink $
                                  %a!href=@here@ reset|]

helplink topic label = [$hamlet|%a!href=$string.u$ $string.label$|]
    where u = manualurl ++ if null topic then "" else '#':topic

addform :: Hamlet HledgerWebAppRoute
addform = [$hamlet|
 %form!method=POST
  %table.form#addform!cellpadding=0!cellspacing=0!border=0
   %tr.formheading
    %td!colspan=4
     %span#formheading Add a transaction:
   %tr
    %td!colspan=4
     %table!cellpadding=0!cellspacing=0!border=0
      %tr#descriptionrow
       %td
        Date:
       %td
        %input!size=15!name=date!value=$string.date$
       %td
        Description:
       %td
        %input!size=35!name=description!value=$string.desc$
      %tr.helprow
       %td
       %td
        #help $string.datehelp$ ^datehelplink^ $
       %td
       %td
        #help $string.deschelp$
   ^transactionfields1^
   ^transactionfields2^
   %tr#addbuttonrow
    %td!colspan=4
     %input!type=submit!value=$string.addlabel$
|]
 where
  datehelplink = helplink "dates" "..."
  datehelp = "eg: 7/20, 2010/1/1, "
  deschelp = "eg: supermarket (optional)"
  addlabel = "add transaction"
  date = "today"
  desc = ""
  transactionfields1 = transactionfields 1
  transactionfields2 = transactionfields 2

-- transactionfields :: Int -> Hamlet String
transactionfields n = [$hamlet|
 %tr#postingrow
  %td!align=right
   $string.label$:
  %td
   %input!size=35!name=$string.acctvar$!value=$string.acct$
  ^amtfield^
 %tr.helprow
  %td
  %td
   #help $string.accthelp$
  %td
  %td
   #help $string.amthelp$
|]
 where
  label | n == 1    = "To account"
        | otherwise = "From account"
  accthelp | n == 1    = "eg: expenses:food"
           | otherwise = "eg: assets:bank:checking"
  amtfield | n == 1 = [$hamlet|
                       %td
                        Amount:
                       %td
                        %input!size=15!name=$string.amtvar$!value=$string.amt$
                       |]
           | otherwise = nulltemplate
  amthelp | n == 1    = "eg: 5, $6, €7.01"
          | otherwise = ""
  acct = ""
  amt = ""
  numbered = (++ show n)
  acctvar = numbered "accountname"
  amtvar = numbered "amount"

postJournalPage :: Handler HledgerWebApp RepPlain
postJournalPage = do
  today <- liftIO getCurrentDay
  -- get form input values. M means a Maybe value.
  (dateM, descM, acct1M, amt1M, acct2M, amt2M) <- runFormPost'
    $ (,,,,,)
    <$> maybeStringInput "date"
    <*> maybeStringInput "description"
    <*> maybeStringInput "accountname1"
    <*> maybeStringInput "amount1"
    <*> maybeStringInput "accountname2"
    <*> maybeStringInput "amount2"
  -- supply defaults and parse date and amounts, or get errors.
  let dateE = maybe (Left "date required") (either (\e -> Left $ showDateParseError e) Right . fixSmartDateStrEither today) dateM
      descE = Right $ fromMaybe "" descM
      acct1E = maybe (Left "to account required") Right acct1M
      acct2E = maybe (Left "from account required") Right acct2M
      amt1E = maybe (Left "amount required") (either (const $ Left "could not parse amount") Right . parse someamount "") amt1M
      amt2E = maybe (Right missingamt)       (either (const $ Left "could not parse amount") Right . parse someamount "") amt2M
      strEs = [dateE, descE, acct1E, acct2E]
      amtEs = [amt1E, amt2E]
      [date,desc,acct1,acct2] = rights strEs
      [amt1,amt2] = rights amtEs
      errs = lefts strEs ++ lefts amtEs
      -- if no errors so far, generate a transaction and balance it or get the error.
      tE | not $ null errs = Left errs
         | otherwise = either (\e -> Left ["unbalanced postings: " ++ (head $ lines e)]) Right
                        (balanceTransaction $ nulltransaction {
                           tdate=parsedate date
                          ,teffectivedate=Nothing
                          ,tstatus=False
                          ,tcode=""
                          ,tdescription=desc
                          ,tcomment=""
                          ,tpostings=[
                            Posting False acct1 amt1 "" RegularPosting Nothing
                           ,Posting False acct2 amt2 "" RegularPosting Nothing
                           ]
                          ,tpreceding_comment_lines=""
                          })
  -- display errors or add transaction
  case tE of
   Left errs -> do
    -- save current form values in session
    setMessage $ string $ intercalate "; " errs
    redirect RedirectTemporary JournalPage

   Right t -> do
    let t' = txnTieKnot t -- XXX move into balanceTransaction
    j <- liftIO $ fromJust `fmap` getValue "hledger" "journal"
    liftIO $ journalAddTransaction j t'
    setMessage $ string $ printf "Added transaction:\n%s" (show t')
    redirect RedirectTemporary JournalPage

getEditPage :: Handler HledgerWebApp RepHtml
getEditPage = do
    -- app <- getYesod
    -- t <- liftIO $ getCurrentLocalTime
    a <- fromMaybe "" <$> lookupGetParam "a"
    p <- fromMaybe "" <$> lookupGetParam "p"
        -- opts = appOpts app ++ [Period p]
        -- args = appArgs app ++ [a]
        -- fspec = optsToFilterSpec opts args t
    -- reload journal's text, without parsing, if changed
    j <- liftIO $ fromJust `fmap` getValue "hledger" "journal"
    changed <- liftIO $ journalFileIsNewer j
    -- XXX readFile may throw an error
    s <- liftIO $ if changed then readFile (filepath j) else return (jtext j)
    -- render the page
    msg <- getMessage
    Just here <- getCurrentRoute
    hamletToRepHtml $ template' here msg a p "hledger" s

template' here msg a p title content = [$hamlet|
!!!
%html
 %head
  %title $string.title$
  %meta!http-equiv=Content-Type!content=$string.metacontent$
  %link!rel=stylesheet!type=text/css!href=@stylesheet@!media=all
 %body
  ^navbar'^
  #messages $m$
  ^editform'^
|]
 where m = fromMaybe (string "") msg
       navbar' = navbar here a p
       stylesheet = StyleCss
       metacontent = "text/html; charset=utf-8"
       editform' = editform content

editform :: String -> Hamlet HledgerWebAppRoute
editform t = [$hamlet|
 %form!method=POST
  %table.form#editform!cellpadding=0!cellspacing=0!border=0
   %tr.formheading
    %td!colspan=2
     %span!style=float:right; ^formhelp^
     %span#formheading Edit journal:
   %tr
    %td!colspan=2
     %textarea!name=text!rows=30!cols=80
      $string.t$
   %tr#addbuttonrow
    %td
     %a!href=@JournalPage@ cancel
    %td!align=right
     %input!type=submit!value=$string.submitlabel$
   %tr.helprow
    %td
    %td!align=right
     #help $string.edithelp$
|]
 where
  submitlabel = "save journal"
  formhelp = helplink "file-format" "file format help"
  edithelp = "Are you sure ? All previous data will be replaced"

postEditPage :: Handler HledgerWebApp RepPlain
postEditPage = do
  -- get form input values, or basic validation errors. E means an Either value.
  textM  <- runFormPost' $ maybeStringInput "text"
  let textE = maybe (Left "No value provided") Right textM
  -- display errors or add transaction
  case textE of
   Left errs -> do
    -- XXX should save current form values in session
    setMessage $ string errs
    redirect RedirectTemporary JournalPage

   Right t' -> do
    -- try to avoid unnecessary backups or saving invalid data
    j <- liftIO $ fromJust `fmap` getValue "hledger" "journal"
    filechanged' <- liftIO $ journalFileIsNewer j
    let f = filepath j
        told = jtext j
        tnew = filter (/= '\r') t'
        changed = tnew /= told || filechanged'
--    changed <- liftIO $ writeFileWithBackupIfChanged f t''
    if not changed
     then do
       setMessage $ string $ "No change"
       redirect RedirectTemporary EditPage
     else do
      jE <- liftIO $ journalFromPathAndString Nothing f tnew
      either
       (\e -> do
          setMessage $ string e
          redirect RedirectTemporary EditPage)
       (const $ do
          liftIO $ writeFileWithBackup f tnew
          setMessage $ string $ printf "Saved journal %s\n" (show f)
          redirect RedirectTemporary JournalPage)
       jE

