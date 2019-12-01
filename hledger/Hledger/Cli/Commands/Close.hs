{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Hledger.Cli.Commands.Close (
  closemode
 ,close
)
where

import Control.Monad (when)
import Data.Function (on)
import Data.List (groupBy)
import Data.Maybe
import qualified Data.Text as T (pack)
import Data.Time.Calendar
import System.Console.CmdArgs.Explicit as C

import Hledger
import Hledger.Cli.CliOptions

defclosingacct = "equity:closing balances"
defopeningacct = "equity:opening balances"

closemode = hledgerCommandMode
  $(embedFileRelative "Hledger/Cli/Commands/Close.txt")
  [flagNone ["closing"] (setboolopt "closing") "show just closing transaction"
  ,flagNone ["opening"] (setboolopt "opening") "show just opening transaction"
  ,flagReq  ["close-to"] (\s opts -> Right $ setopt "close-to" s opts) "ACCT" ("account to transfer closing balances to (default: "++defclosingacct++")")
  ,flagReq  ["open-from"] (\s opts -> Right $ setopt "open-from" s opts) "ACCT" ("account to transfer opening balances from (default: "++defopeningacct++")")
  ]
  [generalflagsgroup1]
  hiddenflags
  ([], Just $ argsFlag "[QUERY]")

close CliOpts{rawopts_=rawopts, reportopts_=ropts} j = do
  today <- getCurrentDay
  let
      (opening, closing) =
        case (boolopt "opening" rawopts, boolopt "closing" rawopts) of
          (False, False) -> (True, True) -- by default show both opening and closing
          (o, c) -> (o, c)
      closingacct = T.pack $ fromMaybe defclosingacct $ maybestringopt "close-to" rawopts
      openingacct = T.pack $ fromMaybe defopeningacct $ maybestringopt "open-from" rawopts
      ropts_ = ropts{balancetype_=HistoricalBalance, accountlistmode_=ALFlat}
      q = queryFromOpts today ropts_
      openingdate = fromMaybe today $ queryEndDate False q
      closingdate = addDays (-1) openingdate
      (acctbals,_) = balanceReportFromMultiBalanceReport ropts_ q j
      balancingamt = negate $ sum $ map (\(_,_,_,b) -> normaliseMixedAmount b) acctbals

      -- since balance assertion amounts are required to be exact, the
      -- amounts in opening/closing transactions should be too (#941, #1137)
      setprec = setFullPrecision
      -- balance assertion amounts will be unpriced (#824)
      -- only the last posting in each commodity will have a balance assertion (#1035)
      closingps = [posting{paccount          = a
                          ,pamount           = mixed [setprec $ negate b]
                          ,pbalanceassertion = if islast then Just assertion{baamount=setprec b{aquantity=0, aprice=Nothing}} else Nothing
                          }
                  | (a,_,_,mb) <- acctbals
                    -- the balances in each commodity, and for each transaction price
                  , let bs = amounts $ normaliseMixedAmount mb
                    -- mark the last balance in each commodity
                  , let bs' = concat [reverse $ zip (reverse bs) (True : repeat False)
                                     | bs <- groupBy ((==) `on` acommodity) bs]
                  , (b, islast) <- bs'
                  ]
                  -- The balancing posting to equity. Allow this one to have a multicommodity amount,
                  -- and don't try to assert its balance.
                  ++
                  [posting{paccount = closingacct
                          ,pamount  = negate balancingamt
                          }
                  ]

      openingps = [posting{paccount          = a
                          ,pamount           = mixed [setprec b]
                          ,pbalanceassertion = case mcommoditysum of
                                                 Just s  -> Just assertion{baamount=setprec s{aprice=Nothing}}
                                                 Nothing -> Nothing
                          }
                  | (a,_,_,mb) <- acctbals
                    -- the balances in each commodity, and for each transaction price
                  , let bs = amounts $ normaliseMixedAmount mb
                    -- mark the last balance in each commodity, with the unpriced sum in that commodity
                  , let bs' = concat [reverse $ zip (reverse bs) (Just commoditysum : repeat Nothing)
                                     | bs <- groupBy ((==) `on` acommodity) bs
                                     , let commoditysum = (sum bs)]
                  , (b, mcommoditysum) <- bs'
                  ]
                  ++
                  [posting{paccount = openingacct
                          ,pamount  = balancingamt
                          }
                  ]

  when closing $ putStr $ showTransaction (nulltransaction{tdate=closingdate, tdescription="closing balances", tpostings=closingps})
  when opening $ putStr $ showTransaction (nulltransaction{tdate=openingdate, tdescription="opening balances", tpostings=openingps})

