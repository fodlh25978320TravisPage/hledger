#!/usr/bin/env runhaskell
{-|
hledger - a ledger-compatible text-based accounting tool.

Copyright (c) 2007-2009 Simon Michael <simon@joyful.com>
Released under GPL version 3 or later.

hledger is a haskell clone of John Wiegley's "ledger" text-based
accounting tool (http://newartisans.com/software/ledger.html).  
It generates ledger-compatible register & balance reports from a plain
text ledger file, and demonstrates a functional implementation of ledger.
For more information, see hledger's home page: http://joyful.com/hledger

You can use the command line:

> $ hledger --help

or ghci:

> $ ghci hledger
> > l <- ledgerfromfilewithopts [] [] "sample.ledger"
> > balance [] [] l
>                  $-1  assets
>                   $2  expenses
>                  $-2  income
>                   $1  liabilities
> > register [] ["income","expenses"] l
> 2008/01/01 income               income:salary                   $-1          $-1
> 2008/06/01 gift                 income:gifts                    $-1          $-2
> 2008/06/03 eat & shop           expenses:food                    $1          $-1
>                                 expenses:supplies                $1            0

-}

module Main (
             module Main,
             module Utils,
             module Options,
             module BalanceCommand,
             module PrintCommand,
             module RegisterCommand,
             module UICommand,
)
where
import Control.Monad.Error
import qualified Data.Map as Map (lookup)
import System.IO

import Ledger
import Utils
import Options
import BalanceCommand
import PrintCommand
import RegisterCommand
import UICommand
import Tests


main :: IO ()
main = do
  (opts, cmd, args) <- parseArguments
  run cmd opts args
    where 
      run cmd opts args
       | Help `elem` opts            = putStr $ usage
       | Version `elem` opts         = putStr version
       | cmd `isPrefixOf` "balance"  = parseLedgerAndDo opts args balance
       | cmd `isPrefixOf` "print"    = parseLedgerAndDo opts args print'
       | cmd `isPrefixOf` "register" = parseLedgerAndDo opts args register
       | cmd `isPrefixOf` "ui"       = parseLedgerAndDo opts args ui
       | cmd `isPrefixOf` "test"     = runtests opts args >> return ()
       | otherwise                   = putStr $ usage

-- | parse the user's specified ledger file and do some action with it
-- (or report a parse error). This function makes the whole thing go.
parseLedgerAndDo :: [Opt] -> [String] -> ([Opt] -> [String] -> Ledger -> IO ()) -> IO ()
parseLedgerAndDo opts args cmd = do
  refdate <- today
  f <- ledgerFilePathFromOpts opts
  -- XXX we read the file twice - inelegant
  -- and, doesn't work with stdin. kludge it, stdin won't work with ui command
  let f' = if f == "-" then "/dev/null" else f
  rawtext <- readFile f'
  let runcmd = cmd opts args . prepareLedger opts args refdate rawtext
  return f >>= runErrorT . parseLedgerFile >>= either (hPutStrLn stderr) runcmd
