{-|

A 'Ledger' stores, for efficiency, a 'RawLedger' plus its tree of account
names, and a map from account names to 'Account's. Typically it also has
had uninteresting 'Entry's filtered out.

-}

module Ledger.Ledger
where
import qualified Data.Map as Map
import Data.Map ((!))
import Ledger.Utils
import Ledger.Types
import Ledger.Amount
import Ledger.AccountName
import Ledger.Account
import Ledger.Transaction
import Ledger.RawLedger
import Ledger.Entry


instance Show Ledger where
    show l = printf "Ledger with %d entries, %d accounts\n%s"
             ((length $ entries $ rawledger l) +
              (length $ modifier_entries $ rawledger l) +
              (length $ periodic_entries $ rawledger l))
             (length $ accountnames l)
             (showtree $ accountnametree l)

-- | Convert a raw ledger to a more efficient cached type, described above.  
cacheLedger :: RawLedger -> Ledger
cacheLedger l = Ledger l ant amap
    where
      ant = rawLedgerAccountNameTree l
      anames = flatten ant
      ts = rawLedgerTransactions l
      sortedts = sortBy (comparing account) ts
      groupedts = groupBy (\t1 t2 -> account t1 == account t2) sortedts
      txnmap = Map.union 
               (Map.fromList [(account $ head g, g) | g <- groupedts])
               (Map.fromList [(a,[]) | a <- anames])
      txnsof = (txnmap !)
      subacctsof a = filter (a `isAccountNamePrefixOf`) anames
      subtxnsof a = concat [txnsof a | a <- [a] ++ subacctsof a]
      balmap = Map.union 
               (Map.fromList [(a,(sumTransactions $ subtxnsof a)) | a <- anames])
               (Map.fromList [(a,[]) | a <- anames])
      amap = Map.fromList [(a, Account a (txnmap ! a) (balmap ! a)) | a <- anames]

-- | List a ledger's account names.
accountnames :: Ledger -> [AccountName]
accountnames l = drop 1 $ flatten $ accountnametree l

-- | Get the named account from a ledger.
ledgerAccount :: Ledger -> AccountName -> Account
ledgerAccount l a = (accountmap l) ! a

-- | List a ledger's accounts, in tree order
accounts :: Ledger -> [Account]
accounts l = drop 1 $ flatten $ ledgerAccountTree 9999 l

-- | List a ledger's top-level accounts, in tree order
topAccounts :: Ledger -> [Account]
topAccounts l = map root $ branches $ ledgerAccountTree 9999 l

-- | Accounts in ledger whose name matches the pattern, in tree order.
-- We apply ledger's special rules for balance report account matching
-- (see 'matchLedgerPatterns').
accountsMatching :: [String] -> Ledger -> [Account]
accountsMatching pats l = filter (matchLedgerPatterns True pats . aname) $ accounts l

-- | List a ledger account's immediate subaccounts
subAccounts :: Ledger -> Account -> [Account]
subAccounts l Account{aname=a} = 
    map (ledgerAccount l) $ filter (a `isAccountNamePrefixOf`) $ accountnames l

-- | List a ledger's transactions.
ledgerTransactions :: Ledger -> [Transaction]
ledgerTransactions l = rawLedgerTransactions $ rawledger l

-- | Get a ledger's tree of accounts to the specified depth.
ledgerAccountTree :: Int -> Ledger -> Tree Account
ledgerAccountTree depth l = treemap (ledgerAccount l) $ treeprune depth $ accountnametree l

-- | Get a ledger's tree of accounts rooted at the specified account.
ledgerAccountTreeAt :: Ledger -> Account -> Maybe (Tree Account)
ledgerAccountTreeAt l acct = subtreeat acct $ ledgerAccountTree 9999 l
