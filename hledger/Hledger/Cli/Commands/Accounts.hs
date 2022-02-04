{-|

The @accounts@ command lists account names:

- in flat mode (default), it lists the full names of accounts posted to by matched postings,
  clipped to the specified depth, possibly with leading components dropped.

- in tree mode, it shows the indented short names of accounts posted to by matched postings,
  and their parents, to the specified depth.

-}

{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Accounts (
  accountsmode
 ,accounts
) where

import Data.List
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Console.CmdArgs.Explicit as C

import Hledger
import Hledger.Cli.CliOptions
import Control.Monad (forM_)


-- | Command line options for this command.
accountsmode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Accounts.txt")
  ([flagNone ["declared"] (setboolopt "declared") "show account names declared with account directives"
  ,flagNone ["used"] (setboolopt "used") "show account names referenced by transactions"
  ,flagNone ["types"] (setboolopt "types") "also show accounts' types, when known"
  ]
  ++ flattreeflags False ++
  [flagReq  ["drop"] (\s opts -> Right $ setopt "drop" s opts) "N" "flat mode: omit N leading account name parts"
  ])
  [generalflagsgroup1]
  hiddenflags
  ([], Just $ argsFlag "[QUERY]")

-- | The accounts command.
accounts :: CliOpts -> Journal -> IO ()
accounts CliOpts{rawopts_=rawopts, reportspec_=ReportSpec{_rsQuery=query,_rsReportOpts=ropts}} j = do

  -- 1. identify the accounts we'll show
  let tree     = tree_ ropts
      declared = boolopt "declared" rawopts
      used     = boolopt "used"     rawopts
      types    = boolopt "types"    rawopts
      -- a depth limit will clip and exclude account names later, but we don't want to exclude accounts at this stage
      nodepthq = dbg1 "nodepthq" $ filterQuery (not . queryIsDepth) query
      -- just the acct: part of the query will be reapplied later, after clipping
      acctq    = dbg1 "acctq" $ filterQuery queryIsAcct query
      depth    = dbg1 "depth" $ queryDepth $ filterQuery queryIsDepth query
      matcheddeclaredaccts =
        dbg1 "matcheddeclaredaccts" $
        filter (matchesAccountExtra (journalAccountType j) (journalInheritedAccountTags j) nodepthq)
          $ map fst $ jdeclaredaccounts j
      matchedusedaccts     = dbg5 "matchedusedaccts" $ map paccount $ journalPostings $ filterJournalPostings nodepthq j
      accts                = dbg5 "accts to show" $ -- no need to nub/sort, accountTree will
        if | declared     && not used -> matcheddeclaredaccts
           | not declared && used     -> matchedusedaccts
           | otherwise                -> matcheddeclaredaccts ++ matchedusedaccts

  -- 2. sort them by declaration order and name, at each level of their tree structure
      sortedaccts = sortAccountNamesByDeclaration j tree accts

  -- 3. if there's a depth limit, depth-clip and remove any no longer useful items
      clippedaccts =
        dbg1 "clippedaccts" $
        filter (matchesAccount acctq) $           -- clipping can leave accounts that no longer match the query, remove such
        nub $                                     -- clipping can leave duplicates (adjacent, hopefully)
        filter (not . T.null) $                   -- depth:0 can leave nulls
        map (clipAccountName depth) $  -- clip at depth if specified
        sortedaccts

  -- 4. print what remains as a list or tree, maybe applying --drop in the former case.
  -- With --types, also show the account type.
  let
    -- some contortions here to show types nicely aligned
    showName a = case accountlistmode_ ropts of
      ALTree -> indent <> accountLeafName droppedName
      ALFlat -> droppedName
      where
        indent      = T.replicate (2 * (max 0 (accountNameLevel a - drop_ ropts) - 1)) " "
        droppedName = accountNameDrop (drop_ ropts) a
    showType a 
      | types     = spacer <> "    ; type: " <> maybe "" (T.pack . show) (journalAccountType j a)
      | otherwise = ""
      where
        spacer = T.replicate (maxwidth - T.length (showName a)) " "
    maxwidth = maximum $ map (T.length . showName) clippedaccts
  forM_ clippedaccts $ \a -> T.putStrLn $ showName a <> showType a
