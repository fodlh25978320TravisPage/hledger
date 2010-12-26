{-|

A 'Posting' represents a 'MixedAmount' being added to or subtracted from a
single 'Account'.  Each 'Transaction' contains two or more postings which
should add up to 0. Postings also reference their parent transaction, so
we can get a date or description for a posting (from the transaction).
Strictly speaking, \"entry\" is probably a better name for these.

-}

module Hledger.Data.Posting
where
import Hledger.Data.Utils
import Hledger.Data.Types
import Hledger.Data.Amount
import Hledger.Data.AccountName
import Hledger.Data.Dates (nulldate, spanContainsDate)


instance Show Posting where show = showPosting

nullposting = Posting False "" nullmixedamt "" RegularPosting [] Nothing

showPosting :: Posting -> String
showPosting (Posting{paccount=a,pamount=amt,pcomment=com,ptype=t}) =
    concatTopPadded [showaccountname a ++ " ", showamount amt, comment]
    where
      ledger3ishlayout = False
      acctnamewidth = if ledger3ishlayout then 25 else 22
      showaccountname = printf ("%-"++(show acctnamewidth)++"s") . bracket . elideAccountName width
      (bracket,width) = case t of
                          BalancedVirtualPosting -> (\s -> "["++s++"]", acctnamewidth-2)
                          VirtualPosting -> (\s -> "("++s++")", acctnamewidth-2)
                          _ -> (id,acctnamewidth)
      showamount = padleft 12 . showMixedAmountOrZero
      comment = if null com then "" else "  ; " ++ com
-- XXX refactor
showPostingForRegister :: Posting -> String
showPostingForRegister (Posting{paccount=a,pamount=amt,ptype=t}) =
    concatTopPadded [showaccountname a ++ " ", showamount amt]
    where
      ledger3ishlayout = False
      acctnamewidth = if ledger3ishlayout then 25 else 22
      showaccountname = printf ("%-"++(show acctnamewidth)++"s") . bracket . elideAccountName width
      (bracket,width) = case t of
                          BalancedVirtualPosting -> (\s -> "["++s++"]", acctnamewidth-2)
                          VirtualPosting -> (\s -> "("++s++")", acctnamewidth-2)
                          _ -> (id,acctnamewidth)
      showamount = padleft 12 . showMixedAmountOrZeroWithoutPrice

isReal :: Posting -> Bool
isReal p = ptype p == RegularPosting

isVirtual :: Posting -> Bool
isVirtual p = ptype p == VirtualPosting

isBalancedVirtual :: Posting -> Bool
isBalancedVirtual p = ptype p == BalancedVirtualPosting

hasAmount :: Posting -> Bool
hasAmount = (/= missingamt) . pamount

postingTypeFromAccountName a
    | head a == '[' && last a == ']' = BalancedVirtualPosting
    | head a == '(' && last a == ')' = VirtualPosting
    | otherwise = RegularPosting

accountNamesFromPostings :: [Posting] -> [AccountName]
accountNamesFromPostings = nub . map paccount

sumPostings :: [Posting] -> MixedAmount
sumPostings = sumMixedAmountsPreservingHighestPrecision . map pamount

postingDate :: Posting -> Day
postingDate p = maybe nulldate tdate $ ptransaction p

-- |Is this posting cleared? If this posting was individually marked
-- as cleared, returns True. Otherwise, return the parent
-- transaction's cleared status or, if there is no parent
-- transaction, return False.
postingCleared :: Posting -> Bool
postingCleared p = if pstatus p
                    then True
                    else maybe False tstatus $ ptransaction p

-- | Does this posting fall within the given date span ?
isPostingInDateSpan :: DateSpan -> Posting -> Bool
isPostingInDateSpan s = spanContainsDate s . postingDate

isEmptyPosting :: Posting -> Bool
isEmptyPosting = isZeroMixedAmount . pamount

-- | Get the minimal date span which contains all the postings, or
-- DateSpan Nothing Nothing if there are none.
postingsDateSpan :: [Posting] -> DateSpan
postingsDateSpan [] = DateSpan Nothing Nothing
postingsDateSpan ps = DateSpan (Just $ postingDate $ head ps') (Just $ addDays 1 $ postingDate $ last ps')
    where ps' = sortBy (comparing postingDate) ps

tests_Hledger_Data_Posting = TestList [
 ]

