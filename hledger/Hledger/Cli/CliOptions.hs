{-|

Common cmdargs modes and flags, a command-line options type, and
related utilities used by hledger commands.

-}

{-# LANGUAGE CPP                 #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE PackageImports      #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}

module Hledger.Cli.CliOptions (
  progname,
  prognameandversion,

  -- * cmdargs flags & modes
  inputflags,
  reportflags,
  helpflags,
  helpflagstitle,
  detailedversionflag,
  flattreeflags,
  hiddenflags,
  -- outputflags,
  outputFormatFlag,
  outputFileFlag,
  generalflagsgroup1,
  generalflagsgroup2,
  generalflagsgroup3,
  mkgeneralflagsgroups1,
  mkgeneralflagsgroups2,
  mkgeneralflagsgroups3,
  cligeneralflagsgroups1,
  cligeneralflagsgroups2,
  cligeneralflagsgroups3,
  defMode,
  defCommandMode,
  addonCommandMode,
  hledgerCommandMode,
  argsFlag,
  showModeUsage,
  withAliases,
  likelyExecutablesInPath,
  hledgerExecutablesInPath,
  ensureDebugHasArg,

  -- * CLI options
  CliOpts(..),
  HasCliOpts(..),
  defcliopts,
  getHledgerCliOpts,
  getHledgerCliOpts',
  rawOptsToCliOpts,
  outputFormats,
  defaultOutputFormat,
  CommandDoc,

  -- possibly these should move into argsToCliOpts
  -- * CLI option accessors
  -- | These do the extra processing required for some options.
  journalFilePathFromOpts,
  rulesFilePathFromOpts,
  outputFileFromOpts,
  outputFormatFromOpts,
  defaultWidth,
  -- widthFromOpts,
  replaceNumericFlags,
  -- | For register:
  registerWidthsFromOpts,

  -- * Other utils
  hledgerAddons,
  topicForMode,

--  -- * Convenience re-exports
--  module Data.String.Here,
--  module System.Console.CmdArgs.Explicit,
)
where

import qualified Control.Exception as C
import Control.Monad (when)
import Data.Char
import Data.Default
import Data.Either (fromRight, isRight)
import Data.List.Extra (groupSortOn, intercalate, isInfixOf, nubSort)
import qualified Data.List.NonEmpty as NE (NonEmpty, fromList, head, nonEmpty)
import Data.List.Split (splitOn)
import Data.Maybe
--import Data.String.Here
-- import Data.Text (Text)
import qualified Data.Text as T
import Data.Void (Void)
import GitHash (tGitInfoCwdTry)
import Safe
import String.ANSI
import System.Console.CmdArgs hiding (Default,def)
import System.Console.CmdArgs.Explicit
import System.Console.CmdArgs.Text
#ifndef mingw32_HOST_OS
import System.Console.Terminfo
#endif
import System.Directory
import System.Environment
import System.Exit (exitSuccess)
import System.FilePath
import System.Info (os)
import Text.Megaparsec
import Text.Megaparsec.Char

import Hledger
import Hledger.Cli.DocFiles
import Hledger.Cli.Version
import Data.Time.Clock.POSIX (POSIXTime)
import Data.List (isPrefixOf, isSuffixOf)


-- | The name of this program's executable.
progname :: ProgramName
progname = "hledger"

-- | Generate the version string for this program.
-- The template haskell call is here rather than in Hledger.Cli.Version to avoid wasteful recompilation.
prognameandversion :: String
prognameandversion =
  versionStringWith
  $$tGitInfoCwdTry
#ifdef GHCDEBUG
  True
#else
  False
#endif
  progname
  packageversion

-- common cmdargs flags
-- keep synced with flag docs in doc/common.m4

-- | Common input-related flags: --file, --rules-file, --alias...
inputflags :: [Flag RawOpts]
inputflags = [
   flagReq  ["file","f"]      (\s opts -> Right $ setopt "file" s opts) "FILE" "Read data from FILE, or from stdin if -. Can be specified more than once. If not specified, reads from $LEDGER_FILE or $HOME/.hledger.journal."
  ,flagReq  ["rules-file"]    (\s opts -> Right $ setopt "rules-file" s opts) "RULEFILE" "Use conversion rules from this file for converting subsequent CSV/SSV/TSV files. If not specified, uses FILE.rules for each such FILE."

  ,flagReq  ["alias"]         (\s opts -> Right $ setopt "alias" s opts)  "A=B|/RGX/=RPL" "transform account names from A to B, or by replacing regular expression matches"
  ,flagNone ["auto"]          (setboolopt "auto") "generate extra postings by applying auto posting rules (\"=\") to all transactions"
  ,flagOpt "" ["forecast"]    (\s opts -> Right $ setopt "forecast" s opts) "PERIOD" (unwords
    [ "Generate extra transactions from periodic rules (\"~\"),"
    , "from after the latest ordinary transaction until 6 months from now. Or, during the specified PERIOD (the equals is required)."
    , "Auto posting rules will also be applied to these transactions."
    , "In hledger-ui, also make future-dated transactions visible at startup."
    ])
  ,flagNone ["ignore-assertions","I"] (setboolopt "ignore-assertions") "don't check balance assertions by default"
  ,flagNone ["infer-costs"] (setboolopt "infer-costs") "infer conversion equity postings from costs"
  ,flagNone ["infer-equity"] (setboolopt "infer-equity") "infer costs from conversion equity postings"
  -- history of this flag so far, lest we be confused:
  --  originally --infer-value
  --  2021-02 --infer-market-price added, --infer-value deprecated
  --  2021-09
  --   --infer-value hidden
  --   --infer-market-price renamed to --infer-market-prices, old spelling still works
  --   ReportOptions{infer_value_} renamed to infer_prices_, BalancingOpts{infer_prices_} renamed to infer_transaction_prices_
  --   some related prices command changes
  --    --costs deprecated and hidden, uses --infer-market-prices instead
  --    --inverted-costs renamed to --infer-reverse-prices
  ,flagNone ["infer-market-prices"] (setboolopt "infer-market-prices") "infer market prices from costs"
  ,flagReq  ["pivot"]         (\s opts -> Right $ setopt "pivot" s opts)  "TAGNAME" "use a different field or tag as account names"
  ,flagNone ["strict","s"]    (setboolopt "strict") "do extra error checks (and override -I)"

  -- generating transactions/postings
  ,flagNone ["verbose-tags"]  (setboolopt "verbose-tags") "add tags indicating generated/modified data"
  ]

-- | Common report-related flags: --period, --cost, etc.
reportflags :: [Flag RawOpts]
reportflags = [

  -- report period & interval
  flagReq  ["begin","b"]     (\s opts -> Right $ setopt "begin" s opts) "DATE" "include postings/transactions on/after this date"
 ,flagReq  ["end","e"]       (\s opts -> Right $ setopt "end" s opts) "DATE" "include postings/transactions before this date (with a report interval, will be adjusted to following subperiod end)"
 ,flagNone ["daily","D"]     (setboolopt "daily")     "multiperiod report with 1 day interval"
 ,flagNone ["weekly","W"]    (setboolopt "weekly")    "multiperiod report with 1 week interval"
 ,flagNone ["monthly","M"]   (setboolopt "monthly")   "multiperiod report with 1 month interval"
 ,flagNone ["quarterly","Q"] (setboolopt "quarterly") "multiperiod report with 1 quarter interval"
 ,flagNone ["yearly","Y"]    (setboolopt "yearly")    "multiperiod report with 1 year interval"
 ,flagReq  ["period","p"]    (\s opts -> Right $ setopt "period" s opts) "PERIODEXP" "set begin date, end date, and/or report interval, with more flexibility"
 ,flagReq  ["today"]         (\s opts -> Right $ setopt "today" s opts) "DATE" "override today's date (affects relative dates)"
 ,flagNone ["date2"]         (setboolopt "date2") "match/use secondary dates instead (deprecated)"  -- see also hiddenflags
 
  -- status/realness/depth/zero filters
 ,flagNone ["unmarked","U"]  (setboolopt "unmarked") "include only unmarked postings/transactions"
 ,flagNone ["pending","P"]   (setboolopt "pending")  "include only pending postings/transactions"
 ,flagNone ["cleared","C"]   (setboolopt "cleared")  "include only cleared postings/transactions\n(-U/-P/-C can be combined)"
 ,flagNone ["real","R"]      (setboolopt "real")     "include only non-virtual postings"
 ,flagReq  ["depth"]         (\s opts -> Right $ setopt "depth" s opts) "NUM" "or -NUM: show only top NUM levels of accounts"
 ,flagNone ["empty","E"]     (setboolopt "empty") "Show zero items, which are normally hidden.\nIn hledger-ui & hledger-web, do the opposite."

  -- valuation
 ,flagNone ["B","cost"]      (setboolopt "B") "show amounts converted to their cost/sale amount"
 ,flagNone ["V","market"]    (setboolopt "V")
    (unlines
      ["Show amounts converted to their value at period end(s) in their default valuation commodity."
      ,"Equivalent to --value=end."
      ])
 ,flagReq ["X","exchange"]   (\s opts -> Right $ setopt "X" s opts) "COMM"
    (unlines
      ["Show amounts converted to their value at period end(s) in the specified commodity."
      ,"Equivalent to --value=end,COMM."
      ])
 ,flagReq  ["value"]         (\s opts -> Right $ setopt "value" s opts) "WHEN[,COMM]"
    (unlines
      ["show amounts converted to their value on the specified date(s) in their default valuation commodity or a specified commodity. WHEN can be:"
      ,"'then':     value on transaction dates"
      ,"'end':      value at period end(s)"
      ,"'now':      value today"
      ,"YYYY-MM-DD: value on given date"
      ])

  -- general output-related
 ,flagReq ["commodity-style", "c"] (\s opts -> Right $ setopt "commodity-style" s opts) "S"
    "Override a commodity's display style.\nEg: -c '$1000.' or -c '1.000,00 EUR'"  
  -- This has special support in hledger-lib:colorOption, keep synced
 ,flagReq  ["color","colour"] (\s opts -> Right $ setopt "color" s opts) "YN"
   (unlines
     ["Use ANSI color codes in text output? Can be"
     ,"'y'/'yes'/'always', 'n'/'no'/'never' or 'auto'."
     ])
 ,flagOpt "yes" ["pretty"] (\s opts -> Right $ setopt "pretty" s opts) "YN"
    "Use box-drawing characters in text output? Can be\n'y'/'yes' or 'n'/'no'.\nIf YN is specified, the equals is required."

 -- flagOpt would be more correct for --debug, showing --debug[=LVL] rather than --debug=[LVL].
 -- But because we handle --debug specially, flagReq also works, and it does not need =, removing a source of confusion.
 -- ,flagOpt "1" ["debug"] (\s opts -> Right $ setopt "debug" s opts) "LVL" "show debug output (levels 1-9, default: 1)"
 ,flagReq  ["debug"]    (\s opts -> Right $ setopt "debug" s opts) "[1-9]" "show this level of debug output (default: 1)"
 ]

helpflags :: [Flag RawOpts]
helpflags = [
  flagNone ["help","h"] (setboolopt "help")    "show command line help"
 ,flagNone ["tldr"]     (setboolopt "tldr")    "show command examples with tldr"
 ,flagNone ["info"]     (setboolopt "info")    "show the manual with info"
 ,flagNone ["man"]      (setboolopt "man")     "show the manual with man"
 ,flagNone ["version"]  (setboolopt "version") "show version information"
 ]
-- XXX why are these duplicated in defCommandMode below ?

-- | A hidden flag just for the hledger executable.
detailedversionflag :: Flag RawOpts
detailedversionflag = flagNone ["version+"] (setboolopt "version+") "show version information with extra detail"

-- | Flags for selecting flat/tree mode, used for reports organised by account.
-- With a True argument, shows some extra help about inclusive/exclusive amounts.
flattreeflags :: Bool -> [Flag RawOpts]
flattreeflags showamounthelp = [
   flagNone ["flat","l"] (setboolopt "flat")
     ("show accounts as a flat list (default)"
      ++ if showamounthelp then ". Amounts exclude subaccount amounts, except where the account is depth-clipped." else "")
  ,flagNone ["tree","t"] (setboolopt "tree")
    ("show accounts as a tree" ++ if showamounthelp then ". Amounts include subaccount amounts." else "")
  ]

-- | Common flags that are accepted but not shown in --help,
-- such as --effective, --aux-date.
hiddenflags :: [Flag RawOpts]
hiddenflags = [
   flagNone ["effective","aux-date"] (setboolopt "date2") "Ledger-compatible aliases for --date2"
  ,flagNone ["infer-value"]          (setboolopt "infer-market-prices") "legacy flag that was renamed"
  ,flagNone ["pretty-tables"]        (setopt "pretty" "always") "legacy flag that was renamed"
  ,flagNone ["anon"]                 (setboolopt "anon") "deprecated, renamed to --obfuscate"  -- #2133, handled by anonymiseByOpts
  ,flagNone ["obfuscate"]            (setboolopt "obfuscate") "slightly obfuscate hledger's output. Warning, does not give privacy. Formerly --anon."  -- #2133, handled by maybeObfuscate
  ]

-- | Common output-related flags: --output-file, --output-format...

-- outputflags = [outputFormatFlag, outputFileFlag]

outputFormatFlag :: [String] -> Flag RawOpts
outputFormatFlag fmts = flagReq
  ["output-format","O"] (\s opts -> Right $ setopt "output-format" s opts) "FMT"
  ("select the output format. Supported formats:\n" ++ intercalate ", " fmts ++ ".")

-- This has special support in hledger-lib:outputFileOption, keep synced
outputFileFlag :: Flag RawOpts
outputFileFlag = flagReq
  ["output-file","o"] (\s opts -> Right $ setopt "output-file" s opts) "FILE"
  "write output to FILE. A file extension matching one of the above formats selects that format."

argsFlag :: FlagHelp -> Arg RawOpts
argsFlag = flagArg (\s opts -> Right $ setopt "args" s opts)

generalflagstitle :: String
generalflagstitle = "\nGeneral flags"

-- Several subsets of the standard general flags, as a single list. Old API used by some addons.
generalflagsgroup1, generalflagsgroup2, generalflagsgroup3 :: (String, [Flag RawOpts])
generalflagsgroup1 = (generalflagstitle, inputflags ++ reportflags ++ helpflags)
generalflagsgroup2 = (generalflagstitle, inputflags ++ helpflags)
generalflagsgroup3 = (generalflagstitle, helpflags)

-- Helpers to make several subsets of the standard general flags, in separate groups. The help flags are parameterised. 2024.
mkgeneralflagsgroups1, mkgeneralflagsgroups2, mkgeneralflagsgroups3 :: [Flag RawOpts] -> [(String, [Flag RawOpts])]
mkgeneralflagsgroups1 helpflags' = [
   (inputflagstitle,  inputflags)
  ,(outputflagstitle, reportflags)
  ,(helpflagstitle,   helpflags')
  ]
mkgeneralflagsgroups2 helpflags' = [
   (inputflagstitle, inputflags)
  ,(helpflagstitle, helpflags')
  ]
mkgeneralflagsgroups3 helpflags' = [
   (helpflagstitle, helpflags')
  ]

inputflagstitle  = "\nGeneral input/data transformation flags"
outputflagstitle = "\nGeneral output/reporting flags (supported by some commands)"
helpflagstitle   = "\nGeneral help flags"

-- Several subsets of the standard general flags plus CLI help flags, as separate groups.
cligeneralflagsgroups1, cligeneralflagsgroups2, cligeneralflagsgroups3 :: [(String, [Flag RawOpts])]
cligeneralflagsgroups1 = mkgeneralflagsgroups1 helpflags
cligeneralflagsgroups2 = mkgeneralflagsgroups2 helpflags
cligeneralflagsgroups3 = mkgeneralflagsgroups3 helpflags


-- cmdargs mode constructors

-- | An empty cmdargs mode to use as a template.
-- Modes describe the top-level command, ie the program, or a subcommand,
-- telling cmdargs how to parse a command line and how to
-- generate the command's usage text.
defMode :: Mode RawOpts
defMode = Mode {
  modeNames       = []            -- program/command name(s)
 ,modeHelp        = ""            -- short help for this command
 ,modeHelpSuffix  = []            -- text displayed after the usage
 ,modeGroupFlags  = Group {       -- description of flags accepted by the command
    groupNamed   = []             --  named groups of flags
   ,groupUnnamed = []             --  ungrouped flags
   ,groupHidden  = []             --  flags not displayed in the usage
   }
 ,modeArgs        = ([], Nothing) -- description of arguments accepted by the command
 ,modeValue       = def           -- value returned when this mode is used to parse a command line
 ,modeCheck       = Right         -- whether the mode's value is correct
 ,modeReform      = const Nothing -- function to convert the value back to a command line arguments
 ,modeExpandAt    = True          -- expand @ arguments for program ?
 ,modeGroupModes  = toGroup []    -- sub-modes
 }

-- | A cmdargs mode suitable for a hledger built-in command
-- with the given names (primary name + optional aliases).
-- The usage message shows [QUERY] as argument.
defCommandMode :: [Name] -> Mode RawOpts
defCommandMode names = defMode {
   modeNames=names
  ,modeGroupFlags  = Group {
     groupNamed   = []
    ,groupUnnamed = [
        flagNone ["help"] (setboolopt "help") "show command-line help"
       ,flagNone ["man"]  (setboolopt "man")  "show this program's user manual with man"
       ,flagNone ["info"] (setboolopt "info") "show this program's user manual with info"
      ]
    ,groupHidden  = []             --  flags not displayed in the usage
    }
  ,modeArgs = ([], Just $ argsFlag "[QUERY]")
  ,modeValue=setopt "command" (headDef "" names) def
  }

-- | A cmdargs mode representing the hledger add-on command with the
-- given name, providing hledger's common input/reporting/help flags.
-- Just used when invoking addons.
addonCommandMode :: Name -> Mode RawOpts
addonCommandMode nam = (defCommandMode [nam]) {
   modeHelp = ""
     -- XXX not needed ?
     -- fromMaybe "" $ lookup (stripAddonExtension name) [
     --   ("addon"        , "dummy add-on command for testing")
     --  ,("addon2"       , "dummy add-on command for testing")
     --  ,("addon3"       , "dummy add-on command for testing")
     --  ,("addon4"       , "dummy add-on command for testing")
     --  ,("addon5"       , "dummy add-on command for testing")
     --  ,("addon6"       , "dummy add-on command for testing")
     --  ,("addon7"       , "dummy add-on command for testing")
     --  ,("addon8"       , "dummy add-on command for testing")
     --  ,("addon9"       , "dummy add-on command for testing")
     --  ]
  ,modeGroupFlags = Group {
      groupUnnamed = []
     ,groupHidden  = hiddenflags
     ,groupNamed   = cligeneralflagsgroups1
     }
  }

-- | A command's documentation. Used both as part of CLI help, and as
-- part of the hledger manual. See parseCommandDoc.
type CommandDoc = String

-- | Build a cmdarg mode for a hledger command,
-- from a help template and flag/argument specifications.
-- Reduces boilerplate a little, though the complicated cmdargs
-- flag and argument specs are still required.
hledgerCommandMode :: CommandDoc -> [Flag RawOpts] -> [(String, [Flag RawOpts])]
  -> [Flag RawOpts] -> ([Arg RawOpts], Maybe (Arg RawOpts)) -> Mode RawOpts
hledgerCommandMode doc unnamedflaggroup namedflaggroups hiddenflaggroup argsdescr =
  case parseCommandDoc doc of
    Nothing -> error' $ "Could not parse command doc:\n"++doc++"\n"  -- PARTIAL:
    Just (names, shorthelp, longhelplines) ->
      (defCommandMode names) {
         modeHelp        = shorthelp
        ,modeHelpSuffix  = longhelplines
        ,modeGroupFlags  = Group {
            groupUnnamed = unnamedflaggroup
           ,groupNamed   = namedflaggroups
           ,groupHidden  = hiddenflaggroup
           }
        ,modeArgs        = argsdescr
        }

-- | Parse a command's help text file (Somecommand.txt).
-- This is generated from the command's doc source file (Somecommand.md)
-- by Shake cmdhelp, and it should be formatted as follows:
--
-- - First line: main command name
--
-- - Third line: command aliases, comma-and-space separated, in parentheses (optional)
--
-- - Fifth or third line to the line containing just _FLAGS (or end of file): short command help
--
-- - Any lines after _FLAGS: long command help
--
-- The CLI --help displays the short help, the flags help generated by cmdargs,
-- then the long help (which some day we might make optional again).
-- The manual displays the short help, then the long help (but not the flags list).
--
parseCommandDoc :: CommandDoc -> Maybe ([Name], String, [String])
parseCommandDoc t =
  case lines t of
    [] -> Nothing
    (l1:_:l3:ls) -> Just (cmdname:cmdaliases, shorthelp, longhelplines)
      where
        cmdname = strip l1
        (cmdaliases, rest) =
          if "(" `isPrefixOf` l3 && ")" `isSuffixOf` l3
          then (words $ filter (/=',') $ drop 1 $ init l3, ls)
          else ([], l3:ls)
        (shorthelpls, longhelpls) = break (== "_FLAGS") $ dropWhile (=="") rest
        shorthelp = unlines $ reverse $ dropWhile null $ reverse shorthelpls
        longhelplines = dropWhile null $ drop 1 longhelpls
    _ -> Nothing  -- error' "misformatted command help text file"

-- | Get a mode's usage message as a nicely wrapped string.
showModeUsage :: Mode a -> String
showModeUsage =
  highlightHelp .
  (showText defaultWrap :: [Text] -> String) .
  (helpText [] HelpFormatDefault :: Mode a -> [Text])

-- | Add some ANSI decoration to cmdargs' help output.
highlightHelp
  | not useColorOnStdout = id
  | otherwise = unlines . zipWith (curry f) [1..] . lines
  where
    f (n,l)
      | n==1 = bold l
      | isHelpHeading l = bold l
      | otherwise = l
    -- keep synced with Hledger.Cli.mainmode:
    isHelpHeading l = isAlphaNum (headDef ' ' l) && (lastDef ' ' l == ':')
      -- any s (`isPrefixOf` s) [
      --    "General input flags"
      --   ,"General reporting flags"
      --   ,"General help flags"
      --   ,"Flags"
      --   ,"General flags"
      --   ,"Examples"
      --   ]
-- | Get the most appropriate documentation topic for a mode.
-- Currently, that is either the hledger, hledger-ui or hledger-web
-- manual.
topicForMode :: Mode a -> Topic
topicForMode m
  | n == "hledger-ui"  = "ui"
  | n == "hledger-web" = "web"
  | otherwise          = "cli"
  where n = headDef "" $ modeNames m

-- | Add command aliases to the command's help string.
withAliases :: String -> [String] -> String
s `withAliases` []     = s
s `withAliases` as = s ++ " (" ++ intercalate ", " as ++ ")"
-- s `withAliases` (a:[]) = s ++ " (alias: " ++ a ++ ")"
-- s `withAliases` as     = s ++ " (aliases: " ++ intercalate ", " as ++ ")"


-- help_postscript = [
--   -- "DATES can be Y/M/D or smart dates like \"last month\"."
--   -- ,"PATTERNS are regular"
--   -- ,"expressions which filter by account name.  Prefix a pattern with desc: to"
--   -- ,"filter by transaction description instead, prefix with not: to negate it."
--   -- ,"When using both, not: comes last."
--  ]


-- CliOpts

-- | Command line options, used in the @hledger@ package and above.
-- This is the \"opts\" used throughout hledger CLI code.
-- representing the options and arguments that were provided at
-- startup on the command-line.
data CliOpts = CliOpts {
     rawopts_         :: RawOpts
    ,command_         :: String
    ,file_            :: [FilePath]
    ,inputopts_       :: InputOpts
    ,reportspec_      :: ReportSpec
    ,output_file_     :: Maybe FilePath
    ,output_format_   :: Maybe String
    ,debug_           :: Int            -- ^ debug level, set by @--debug[=N]@. See also 'Hledger.Utils.debugLevel'.
    ,no_new_accounts_ :: Bool           -- add
    ,width_           :: Maybe String   -- ^ the --width value provided, if any
    ,available_width_ :: Int            -- ^ estimated usable screen width, based on
                                        -- 1. the COLUMNS env var, if set
                                        -- 2. the width reported by the terminal, if supported
                                        -- 3. the default (80)
    ,progstarttime_   :: POSIXTime      -- system POSIX time at start
 } deriving (Show)

instance Default CliOpts where def = defcliopts

defcliopts :: CliOpts
defcliopts = CliOpts
    { rawopts_         = def
    , command_         = ""
    , file_            = []
    , inputopts_       = definputopts
    , reportspec_      = def
    , output_file_     = Nothing
    , output_format_   = Nothing
    , debug_           = 0
    , no_new_accounts_ = False
    , width_           = Nothing
    , available_width_ = defaultWidth
    , progstarttime_   = 0
    }

-- | Default width for hledger console output, when not otherwise specified.
defaultWidth :: Int
defaultWidth = 80

-- | Replace any numeric flags (eg -2) with their long form (--depth 2),
-- as I'm guessing cmdargs doesn't support this directly.
replaceNumericFlags :: [String] -> [String]
replaceNumericFlags = map replace
  where
    replace ('-':ds) | not (null ds) && all isDigit ds = "--depth="++ds
    replace s = s

-- | Parse raw option string values to the desired final data types.
-- Any relative smart dates will be converted to fixed dates based on
-- today's date. Parsing failures will raise an error.
-- Also records the terminal width, if supported.
rawOptsToCliOpts :: RawOpts -> IO CliOpts
rawOptsToCliOpts rawopts = do
  currentDay <- getCurrentDay
  let day = case maybestringopt "today" rawopts of
              Nothing -> currentDay
              Just d  -> fromRight (error' $ "Unable to parse date \"" ++ d ++ "\"") $ -- PARTIAL:
                         fromEFDay <$> fixSmartDateStrEither' currentDay (T.pack d)
  let iopts = rawOptsToInputOpts day rawopts
  rspec <- either error' pure $ rawOptsToReportSpec day rawopts  -- PARTIAL:
  mcolumns <- readMay <$> getEnvSafe "COLUMNS"
  mtermwidth <-
#ifdef mingw32_HOST_OS
    return Nothing
#else
    (`getCapability` termColumns) <$> setupTermFromEnv
    -- XXX Throws a SetupTermError if the terminfo database could not be read, should catch
#endif
  let availablewidth = NE.head $ NE.fromList $ catMaybes [mcolumns, mtermwidth, Just defaultWidth]  -- PARTIAL: fromList won't fail because non-null list
  return defcliopts {
              rawopts_         = rawopts
             ,command_         = stringopt "command" rawopts
             ,file_            = listofstringopt "file" rawopts
             ,inputopts_       = iopts
             ,reportspec_      = rspec
             ,output_file_     = maybestringopt "output-file" rawopts
             ,output_format_   = maybestringopt "output-format" rawopts
             ,debug_           = posintopt "debug" rawopts
             ,no_new_accounts_ = boolopt "no-new-accounts" rawopts -- add
             ,width_           = maybestringopt "width" rawopts
             ,available_width_ = availablewidth
             }

-- | A helper for addon commands: this parses options and arguments from
-- the current command line using the given hledger-style cmdargs mode,
-- and returns a CliOpts. Or, with --help or -h present, it prints
-- long or short help, and exits the program.
-- When --debug is present, also prints some debug output.
-- Note this is not used by the main hledger executable.
--
-- The help texts are generated from the mode.
-- Long help includes the full usage description generated by cmdargs
-- (including all supported options), framed by whatever pre- and postamble
-- text the mode specifies. It's intended that this forms a complete
-- help document or manual.
--
-- Short help is a truncated version of the above: the preamble and
-- the first part of the usage, up to the first line containing "flags:"
-- (normally this marks the start of the common hledger flags);
-- plus a mention of --help and the (presumed supported) common
-- hledger options not displayed.
--
-- Tips:
-- Empty lines in the pre/postamble are removed by cmdargs;
-- add a space character to preserve them.
--
getHledgerCliOpts' :: Mode RawOpts -> [String] -> IO CliOpts
getHledgerCliOpts' mode' args0 = do
  let rawopts = either usageError id $ process mode' args0
  opts <- rawOptsToCliOpts rawopts
  debugArgs args0 opts
  when (boolopt "help" $ rawopts_ opts) $ putStr shorthelp >> exitSuccess
  -- when (boolopt "help" $ rawopts_ opts) $ putStr longhelp  >> exitSuccess
  return opts
  where
    longhelp = showModeUsage mode'
    shorthelp =
      unlines $
        (reverse $ dropWhile null $ reverse $ takeWhile (not . ("flags:" `isInfixOf`)) $ lines longhelp)
        ++
        [""
        ,"  See also hledger -h for general hledger options."
        ]
    -- | Print debug info about arguments and options if --debug is present.
    -- XXX use standard dbg helpers
    debugArgs :: [String] -> CliOpts -> IO ()
    debugArgs args1 opts =
      when ("--debug" `elem` args1) $ do
        progname' <- getProgName
        putStrLn $ "running: " ++ progname'
        putStrLn $ "raw args: " ++ show args1
        putStrLn $ "processed opts:\n" ++ show opts
        putStrLn $ "search query: " ++ show (_rsQuery $ reportspec_ opts)

getHledgerCliOpts :: Mode RawOpts -> IO CliOpts
getHledgerCliOpts mode' = do
  args' <- getArgs >>= expandArgsAt
  getHledgerCliOpts' mode' args' 

-- CliOpts accessors

-- | Get the (tilde-expanded, absolute) journal file path from
-- 1. options, 2. an environment variable, or 3. the default.
-- Actually, returns one or more file paths. There will be more
-- than one if multiple -f options were provided.
-- File paths can have a READER: prefix naming a reader/data format.
journalFilePathFromOpts :: CliOpts -> IO (NE.NonEmpty String)
journalFilePathFromOpts opts = do
  f <- defaultJournalPath
  d <- getCurrentDirectory
  maybe
    (return $ NE.fromList [f])
    (mapM (expandPathPreservingPrefix d))
    $ NE.nonEmpty $ file_ opts

expandPathPreservingPrefix :: FilePath -> PrefixedFilePath -> IO PrefixedFilePath
expandPathPreservingPrefix d prefixedf = do
  let (p,f) = splitReaderPrefix prefixedf
  f' <- expandPath d f
  return $ case p of
    Just p'  -> (show p') ++ ":" ++ f'
    Nothing -> f'

-- | Get the expanded, absolute output file path specified by an
-- -o/--output-file options, or nothing, meaning stdout.
outputFileFromOpts :: CliOpts -> IO (Maybe FilePath)
outputFileFromOpts opts = do
  d <- getCurrentDirectory
  case output_file_ opts of
    Nothing -> return Nothing
    Just f  -> Just <$> expandPath d f

defaultOutputFormat :: String
defaultOutputFormat = "txt"

-- | All the output formats known by any command, for outputFormatFromOpts.
-- To automatically infer it from -o/--output-file, it needs to be listed here.
outputFormats :: [String]
outputFormats = [defaultOutputFormat, "beancount", "csv", "json", "html", "sql", "tsv"]

-- | Get the output format from the --output-format option,
-- otherwise from a recognised file extension in the --output-file option,
-- otherwise the default (txt).
outputFormatFromOpts :: CliOpts -> String
outputFormatFromOpts opts =
  case output_format_ opts of
    Just f  -> f
    Nothing ->
      case filePathExtension <$> output_file_ opts of
        Just ext | ext `elem` outputFormats -> ext
        _                                   -> defaultOutputFormat

-- -- | Get the file name without its last extension, from a file path.
-- filePathBaseFileName :: FilePath -> String
-- filePathBaseFileName = fst . splitExtension . snd . splitFileName

-- | Get the last file extension, without the dot, from a file path.
-- May return the null string.
filePathExtension :: FilePath -> String
filePathExtension = dropWhile (=='.') . snd . splitExtension . snd . splitFileName

-- | Get the (tilde-expanded) rules file path from options, if any.
rulesFilePathFromOpts :: CliOpts -> IO (Maybe FilePath)
rulesFilePathFromOpts opts = do
  d <- getCurrentDirectory
  maybe (return Nothing) (fmap Just . expandPath d) $ mrules_file_ $ inputopts_ opts

-- -- | Get the width in characters to use for console output.
-- -- This comes from the --width option, or the COLUMNS environment
-- -- variable, or (on posix platforms) the current terminal width, or 80.
-- -- Will raise a parse error for a malformed --width argument.
-- widthFromOpts :: CliOpts -> Int
-- widthFromOpts CliOpts{width_=Nothing, available_width_=w} = w
-- widthFromOpts CliOpts{width_=Just s}  =
--     case runParser (read `fmap` some digitChar <* eof :: ParsecT Void String Identity Int) "(unknown)" s of
--         Left e   -> usageError $ "could not parse width option: "++errorBundlePretty e
--         Right w  -> w

-- for register:

-- | Get the width in characters to use for the register command's console output,
-- and also the description column width if specified (following the main width, comma-separated).
-- The widths will be as follows:
-- @
-- no --width flag - overall width is the available width (COLUMNS, or posix terminal width, or 80); description width is unspecified (auto)
-- --width W       - overall width is W, description width is auto
-- --width W,D     - overall width is W, description width is D
-- @
-- Will raise a parse error for a malformed --width argument.
registerWidthsFromOpts :: CliOpts -> (Int, Maybe Int)
registerWidthsFromOpts CliOpts{width_=Nothing, available_width_=w} = (w, Nothing)
registerWidthsFromOpts CliOpts{width_=Just s}  =
    case runParser registerwidthp "(unknown)" s of
        Left e   -> usageError $ "could not parse width option: "++errorBundlePretty e
        Right ws -> ws
    where
        registerwidthp :: (Stream s, Char ~ Token s) => ParsecT Void s m (Int, Maybe Int)
        registerwidthp = do
          totalwidth <- read `fmap` some digitChar
          descwidth <- optional (char ',' >> read `fmap` some digitChar)
          eof
          return (totalwidth, descwidth)

-- Other utils

-- | Get the sorted unique canonical names of hledger addon commands
-- found in the current user's PATH. These are used in command line
-- parsing and to display the commands list.
--
-- Canonical addon names are the filenames of hledger-* executables in
-- PATH, without the "hledger-" prefix, and without the file extension
-- except when it's needed for disambiguation (see below).
--
-- When there are exactly two versions of an executable (same base
-- name, different extensions) that look like a source and compiled
-- pair (one has .exe, .com, or no extension), the source version will
-- be excluded (even if it happens to be newer). When there are three
-- or more versions (or two versions that don't look like a
-- source/compiled pair), they are all included, with file extensions
-- intact.
--
hledgerAddons :: IO [String]
hledgerAddons = do
  -- past bug generator
  as1 <- hledgerExecutablesInPath                     -- ["hledger-check","hledger-check-dates","hledger-check-dates.hs","hledger-check.hs","hledger-check.py"]
  let as2 = map stripPrognamePrefix as1               -- ["check","check-dates","check-dates.hs","check.hs","check.py"]
  let as3 = groupSortOn takeBaseName as2              -- [["check","check.hs","check.py"],["check-dates","check-dates.hs"]]
  let as4 = concatMap dropRedundantSourceVersion as3  -- ["check","check.hs","check.py","check-dates"]
  return as4

stripPrognamePrefix = drop (length progname + 1)

dropRedundantSourceVersion [f,g]
  | map toLower (takeExtension f) `elem` compiledExts = [f]
  | map toLower (takeExtension g) `elem` compiledExts = [g]
dropRedundantSourceVersion fs = fs

compiledExts = ["",".com",".exe"]

-- | Get the sorted unique filenames of all hledger-* executables in
-- the current user's PATH. These are files in any of the PATH directories,
-- named hledger-*, with either no extension (and no periods in the name)
-- or one of the addonExtensions.
-- We do not currently filter out non-file objects or files without execute permission.
hledgerExecutablesInPath :: IO [String]
hledgerExecutablesInPath = filter isHledgerExeName <$> likelyExecutablesInPath

-- None of https://hackage.haskell.org/package/directory-1.3.8.1/docs/System-Directory.html#g:5
-- do quite what we need (find all the executables in PATH with a filename prefix).
-- | Get all sorted unique filenames in the current user's PATH.
-- We do not currently filter out non-file objects or files without execute permission.
likelyExecutablesInPath :: IO [String]
likelyExecutablesInPath = do
  pathdirs <- splitOn pathsep `fmap` getEnvSafe "PATH"
  pathfiles <- concat `fmap` mapM getDirectoryContentsSafe pathdirs
  return $ nubSort pathfiles
  where pathsep = if os == "mingw32" then ";" else ":"
--
-- Exclude directories and files without execute permission:
-- this would do a stat for each hledger-* file found, which is probably ok.
-- But it needs file paths, not just file names.
--
-- exes'  <- filterM doesFileExist exe'
-- exes'' <- filterM isExecutable exes'
-- return exes''
-- where isExecutable f = getPermissions f >>= (return . executable)

isHledgerExeName :: String -> Bool
isHledgerExeName = isRight . parsewith hledgerexenamep . T.pack
    where
      hledgerexenamep = do
        _ <- string $ T.pack progname
        _ <- char '-'
        _ <- some $ noneOf ['.']
        optional (string "." >> choice' (map (string . T.pack) addonExtensions))
        eof

-- stripAddonExtension :: String -> String
-- stripAddonExtension = regexReplace re "" where re = "\\.(" ++ intercalate "|" addonExtensions ++ ")$"

addonExtensions :: [String]
addonExtensions =
  ["bat"
  ,"com"
  ,"exe"
  ,"hs"
  ,"js"
  ,"lhs"
  ,"lua"
  ,"php"
  ,"pl"
  ,"py"
  ,"rb"
  ,"rkt"
  ,"sh"
  -- ,""
  ]

getEnvSafe :: String -> IO String
getEnvSafe v = getEnv v `C.catch` (\(_::C.IOException) -> return "") -- XXX should catch only isDoesNotExistError e

getDirectoryContentsSafe :: FilePath -> IO [String]
getDirectoryContentsSafe d =
    (filter (not . (`elem` [".",".."])) `fmap` getDirectoryContents d) `C.catch` (\(_::C.IOException) -> return [])

-- not used:
-- -- | Print debug info about arguments and options if --debug is present.
-- debugArgs :: [String] -> CliOpts -> IO ()
-- debugArgs args opts =
--   when ("--debug" `elem` args) $ do
--     progname <- getProgName
--     putStrLn $ "running: " ++ progname
--     putStrLn $ "raw args: " ++ show args
--     putStrLn $ "processed opts:\n" ++ show opts
--     d <- getCurrentDay
--     putStrLn $ "search query: " ++ (show $ queryFromOpts d $ reportopts_ opts)

-- ** Lenses

makeHledgerClassyLenses ''CliOpts

instance HasInputOpts CliOpts where
    inputOpts = inputopts

instance HasBalancingOpts CliOpts where
    balancingOpts = inputOpts.balancingOpts

instance HasReportSpec CliOpts where
    reportSpec = reportspec

instance HasReportOptsNoUpdate CliOpts where
    reportOptsNoUpdate = reportSpec.reportOptsNoUpdate

instance HasReportOpts CliOpts where
    reportOpts = reportSpec.reportOpts

-- | Convert an argument-less --debug flag to --debug=1 in the given arguments list.
-- Used by hledger/ui/web to make their command line parsing easier somehow.
ensureDebugHasArg as = case break (=="--debug") as of
  (bs,"--debug":c:cs) | null c || not (all isDigit c) -> bs++"--debug=1":c:cs
  (bs,["--debug"])                                    -> bs++["--debug=1"]
  _                                                   -> as
