{-| 

A ledger-compatible @balance@ command. Here's how it should work:

A sample account tree (as in the sample.ledger file):

@
 assets
  cash
  checking
  saving
 expenses
  food
  supplies
 income
  gifts
  salary
 liabilities
  debts
@

The balance command shows top-level accounts by default:

@
 \> ledger balance
 $-1  assets
  $2  expenses
 $-2  income
  $1  liabilities
@

With -s (--subtotal), also show the subaccounts:

@
 $-1  assets
 $-2    cash
  $1    saving
  $2  expenses
  $1    food
  $1    supplies
 $-2  income
 $-1    gifts
 $-1    salary
  $1  liabilities:debts
@

- @checking@ is not shown because it has a zero balance and no interesting
  subaccounts.  

- @liabilities@ is displayed only as a prefix because it has the same balance
  as its single subaccount.

With an account pattern, show only the accounts with matching names:

@
 \> ledger balance o
  $1  expenses:food
 $-2  income
--------------------
 $-1  
@

- The o matched @food@ and @income@, so they are shown.

- Parents of matched accounts are also shown for context (@expenses@).

- This time the grand total is also shown, because it is not zero.

Again, -s adds the subaccounts:

@
\> ledger -s balance o
  $1  expenses:food
 $-2  income
 $-1    gifts
 $-1    salary
--------------------
 $-1  
@

- @food@ has no subaccounts. @income@ has two, so they are shown. 

- We do not add the subaccounts of parents included for context (@expenses@).

Some notes for the implementation:

- a simple balance report shows top-level accounts

- with an account pattern, it shows accounts whose leafname matches, plus their parents

- with the subtotal option, it also shows all subaccounts of the above

- zero-balance leaf accounts are removed

- the resulting account tree is displayed with each account's aggregated
  balance, with boring parents prefixed to the next line

- a boring parent has the same balance as its child and is not explicitly
  matched by the display options.

- the sum of the balances shown is displayed at the end, if it is non-zero

-}

module BalanceCommand
where
import Ledger.Utils
import Ledger.Types
import Ledger.Amount
import Ledger.AccountName
import Ledger.Ledger
import Options
import Utils


-- | Print a balance report.
balance :: [Opt] -> [String] -> Ledger -> IO ()
balance opts args l = putStr $ showBalanceReport opts args l

-- | Generate balance report output for a ledger, based on options.
showBalanceReport :: [Opt] -> [String] -> Ledger -> String
showBalanceReport opts args l = acctsstr ++ totalstr
    where 
      acctsstr = concatMap (showAccountTreeWithBalances acctnamestoshow) $ subs treetoshow
      totalstr = if isZeroMixedAmount total 
                 then "" 
                 else printf "--------------------\n%20s\n" $ showMixedAmount total
      showingsubs = SubTotal `elem` opts
      pats@(apats,dpats) = parseAccountDescriptionArgs args
      maxdepth = if null args && not showingsubs then 1 else 9999
      acctstoshow = balancereportaccts showingsubs apats l
      acctnamestoshow = map aname acctstoshow
      treetoshow = pruneZeroBalanceLeaves $ pruneUnmatchedAccounts $ treeprune maxdepth $ ledgerAccountTree 9999 l
      total = sum $ map abalance $ nonredundantaccts
      nonredundantaccts = filter (not . hasparentshowing) acctstoshow
      hasparentshowing a = (parentAccountName $ aname a) `elem` acctnamestoshow

      -- select accounts for which we should show balances, based on the options
      balancereportaccts :: Bool -> [String] -> Ledger -> [Account]
      balancereportaccts False [] l = topAccounts l
      balancereportaccts False pats l = accountsMatching pats l
      balancereportaccts True pats l = addsubaccts l $ balancereportaccts False pats l

      -- add (in tree order) any missing subacccounts to a list of accounts
      addsubaccts :: Ledger -> [Account] -> [Account]
      addsubaccts l as = concatMap addsubs as where addsubs = maybe [] flatten . ledgerAccountTreeAt l

      -- remove any accounts from the tree which are not one of the acctstoshow, 
      -- or one of their parents, or one of their subaccounts when doing --subtotal
      pruneUnmatchedAccounts :: Tree Account -> Tree Account
      pruneUnmatchedAccounts = treefilter matched
          where 
            matched (Account name _ _)
                | name `elem` acctnamestoshow = True
                | any (name `isAccountNamePrefixOf`) acctnamestoshow = True
                | showingsubs && any (`isAccountNamePrefixOf` name) acctnamestoshow = True
                | otherwise = False

      -- remove zero-balance leaf accounts (recursively)
      pruneZeroBalanceLeaves :: Tree Account -> Tree Account
      pruneZeroBalanceLeaves = treefilter (not . isZeroMixedAmount . abalance)

-- | Show a tree of accounts with balances, for the balance report,
-- eliding boring parent accounts. Requires a list of the account names we
-- are interested in to help with that.
showAccountTreeWithBalances :: [AccountName] -> Tree Account -> String
showAccountTreeWithBalances matchednames = 
    showAccountTreeWithBalances' matchednames 0 ""
    where
      showAccountTreeWithBalances' :: [AccountName] -> Int -> String -> Tree Account -> String
      showAccountTreeWithBalances' matchednames indent prefix (Node (Account fullname _ bal) subs)
          | not isboringparent = this ++ subswithindent
          | otherwise = subswithprefix
          where
            subswithindent = showsubs (indent+1) ""
            subswithprefix = showsubs indent (prefix++leafname++":")
            showsubs i p = concatMap (showAccountTreeWithBalances' matchednames i p) subs
            this = showbal ++ spaces ++ prefix ++ leafname ++ "\n"
            showbal = printf "%20s" $ showMixedAmount bal
            spaces = "  " ++ replicate (indent * 2) ' '
            leafname = accountLeafName fullname
            isboringparent = numsubs >= 1 && (bal == subbal || not matched)
            numsubs = length subs
            subbal = abalance $ root $ head subs
            matched = fullname `elem` matchednames
