{-|

A 'Transaction' is a 'Posting' with its parent 'LedgerTransaction' \'s date and
description attached. These are what we actually query when doing reports.

-}

module Ledger.Transaction
where
import Ledger.Utils
import Ledger.Types
import Ledger.Dates
import Ledger.LedgerTransaction
import Ledger.Posting
import Ledger.Amount


instance Show Transaction where show=showTransaction

showTransaction :: Transaction -> String
showTransaction (Transaction eno stat d desc a amt ttype) = 
    s ++ unwords [showDate d,desc,a,show amt,show ttype]
    where s = if stat then " *" else ""

-- | Convert a 'LedgerTransaction' to two or more 'Transaction's. An id number
-- is attached to the transactions to preserve their grouping - it should
-- be unique per entry.
flattenLedgerTransaction :: (LedgerTransaction, Int) -> [Transaction]
flattenLedgerTransaction (LedgerTransaction d s _ desc _ ps _, n) = 
    [Transaction n s d desc (paccount p) (pamount p) (ptype p) | p <- ps]

accountNamesFromTransactions :: [Transaction] -> [AccountName]
accountNamesFromTransactions ts = nub $ map account ts

sumTransactions :: [Transaction] -> MixedAmount
sumTransactions = sum . map amount

nulltxn = Transaction 0 False (parsedate "1900/1/1") "" "" nullmixedamt RegularPosting
