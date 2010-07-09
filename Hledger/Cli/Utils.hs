{-# LANGUAGE CPP #-}
{-|

Utilities for top-level modules and ghci. See also Hledger.Read and
Hledger.Data.Utils.

-}

module Hledger.Cli.Utils
    (
     withJournalDo,
     readJournalWithOpts,
     journalReload,
     journalReloadIfChanged,
     journalFileIsNewer,
     journalFileModificationTime,
     openBrowserOn,
     writeFileWithBackup,
     writeFileWithBackupIfChanged,
    )
where
import Control.Exception (SomeException(..), try)
import Hledger.Data
import Hledger.Read
import Hledger.Cli.Options (Opt(..),journalFilePathFromOpts) -- ,optsToFilterSpec)
import Safe (readMay)
import System.Directory (doesFileExist, getModificationTime, getDirectoryContents, copyFile)
import System.Exit
import System.FilePath ((</>), splitFileName, takeDirectory)
import System.Info (os)
import System.Process (readProcessWithExitCode)
import System.Time (ClockTime, getClockTime, diffClockTimes, TimeDiff(TimeDiff))


-- | Parse the user's specified journal file and run a hledger command on
-- it, or throw an error.
withJournalDo :: [Opt] -> [String] -> String -> ([Opt] -> [String] -> Journal -> IO ()) -> IO ()
withJournalDo opts args cmdname cmd = do
  -- We kludgily read the file before parsing to grab the full text, unless
  -- it's stdin, or it doesn't exist and we are adding. We read it strictly
  -- to let the add command work.
  f <- journalFilePathFromOpts opts
  fileexists <- doesFileExist f
  let creating = not fileexists && cmdname == "add"
      costify = (if CostBasis `elem` opts then journalConvertAmountsToCost else id)
      runcmd = cmd opts args . costify
  if creating
   then runcmd nulljournal
   else readJournalFile Nothing f >>= runcmd

-- | Get a journal from the given string and options, or throw an error.
readJournalWithOpts :: [Opt] -> String -> IO Journal
readJournalWithOpts opts s = do
    j <- readJournal Nothing s
    let cost = CostBasis `elem` opts
    return $ (if cost then journalConvertAmountsToCost else id) j

-- | Re-read a journal from its data file, or return the exception that was raised.
journalReload :: Journal -> IO (Either SomeException Journal)
journalReload Journal{filepath=f} = try $ readJournalFile Nothing f

-- | Re-read a journal from its data file mostly, only if the file has
-- changed since last read (or if there is no file, ie data read from
-- stdin). The provided options are mostly ignored. Return a journal or
-- the exception that was raised while reading it, and a flag indicating
-- whether it was re-read or not.
journalReloadIfChanged :: [Opt] -> Journal -> IO (Bool, Either SomeException Journal)
journalReloadIfChanged opts j@Journal{filepath=f} = do
  changed <- journalFileIsNewer j
  if changed
   then do
     when (Verbose `elem` opts) $ printf "%s has changed, reloading\n" f
     jE <- journalReload j
     return (True, jE)
   else
     return (False, Right j)

-- | Has the journal's data file changed since last parsed ?
journalFileIsNewer :: Journal -> IO Bool
journalFileIsNewer j@Journal{filereadtime=tread} = do
  tmod <- journalFileModificationTime j
  return $ diffClockTimes tmod tread > (TimeDiff 0 0 0 0 0 0 0)

-- | Get the last modified time of the journal's data file (or if there is no
-- file, the current time).
journalFileModificationTime :: Journal -> IO ClockTime
journalFileModificationTime Journal{filepath=f}
    | null f = getClockTime
    | otherwise = getModificationTime f `Prelude.catch` \_ -> getClockTime

-- | Attempt to open a web browser on the given url, all platforms.
openBrowserOn :: String -> IO ExitCode
openBrowserOn u = trybrowsers browsers u
    where
      trybrowsers (b:bs) u = do
        (e,_,_) <- readProcessWithExitCode b [u] ""
        case e of
          ExitSuccess -> return ExitSuccess
          ExitFailure _ -> trybrowsers bs u
      trybrowsers [] u = do
        putStrLn $ printf "Sorry, I could not start a browser (tried: %s)" $ intercalate ", " browsers
        putStrLn $ printf "Please open your browser and visit %s" u
        return $ ExitFailure 127
      browsers | os=="darwin"  = ["open"]
               | os=="mingw32" = ["start"]
               | otherwise     = ["sensible-browser","gnome-www-browser","firefox"]
    -- jeffz: write a ffi binding for it using the Win32 package as a basis
    -- start by adding System/Win32/Shell.hsc and follow the style of any
    -- other module in that directory for types, headers, error handling and
    -- what not.
    -- ::ShellExecute(NULL, "open", "www.somepage.com", NULL, NULL, SW_SHOWNORMAL);
    -- ::ShellExecute(NULL, "open", "firefox.exe", "www.somepage.com" NULL, SW_SHOWNORMAL);

-- | Back up this file with a (incrementing) numbered suffix then
-- overwrite it with this new text, or give an error, but only if the text
-- is different from the current file contents, and return a flag
-- indicating whether we did anything.
writeFileWithBackupIfChanged :: FilePath -> String -> IO Bool
writeFileWithBackupIfChanged f t = do
  s <- readFile f
  if t == s then return False
            else backUpFile f >> writeFile f t >> return True

-- | Back up this file with a (incrementing) numbered suffix, then
-- overwrite it with this new text, or give an error.
writeFileWithBackup :: FilePath -> String -> IO ()
writeFileWithBackup f t = backUpFile f >> writeFile f t

-- | Back up this file with a (incrementing) numbered suffix, or give an error.
backUpFile :: FilePath -> IO ()
backUpFile fp = do
  fs <- getDirectoryContents $ takeDirectory fp
  let (d,f) = splitFileName fp
      versions = catMaybes $ map (f `backupNumber`) fs
      next = maximum (0:versions) + 1
      f' = printf "%s.%d" f next
  copyFile fp (d </> f')

-- | Does the second file represent a backup of the first, and if so which version is it ?
backupNumber :: FilePath -> FilePath -> Maybe Int
backupNumber f g = case matchRegexPR ("^" ++ f ++ "\\.([0-9]+)$") g of
                        Just (_, ((_,suffix):_)) -> readMay suffix
                        _ -> Nothing
