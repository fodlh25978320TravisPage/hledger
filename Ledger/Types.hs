{-# LANGUAGE DeriveDataTypeable #-}
{-|

Most data types are defined here to avoid import cycles.
Here is an overview of the hledger data model as of 0.8:

 Ledger              -- hledger's ledger, a journal file plus various cached data
  Journal            -- representation of the journal file
   [Transaction]     -- journal transactions, with date, description and..
    [Posting]        -- one or more journal postings
  [LedgerPosting]    -- all postings combined with their transaction info
  Tree AccountName   -- the tree of all account names
  Map AccountName Account -- per-account ledger postings and balances for easy lookup

For more detailed documentation on each type, see the corresponding modules.

A note about terminology:

  - ledger 2 had entries containing transactions.

  - ledger 3 has transactions containing postings.

  - hledger 0.4 had Entrys containing RawTransactions, which were flattened to Transactions.

  - hledger 0.5 had LedgerTransactions containing Postings, which were flattened to Transactions.

  - hledger 0.8 has Transactions containing Postings, which are flattened to LedgerPostings.

-}

module Ledger.Types 
where
import Ledger.Utils
import qualified Data.Map as Map
import System.Time (ClockTime)
import Data.Typeable (Typeable)


type SmartDate = (String,String,String)

data WhichDate = ActualDate | EffectiveDate

data DateSpan = DateSpan (Maybe Day) (Maybe Day) deriving (Eq,Show,Ord)

data Interval = NoInterval | Daily | Weekly | Monthly | Quarterly | Yearly 
                deriving (Eq,Show,Ord)

type AccountName = String

data Side = L | R deriving (Eq,Show,Ord) 

data Commodity = Commodity {
      symbol :: String,  -- ^ the commodity's symbol
      -- display preferences for amounts of this commodity
      side :: Side,      -- ^ should the symbol appear on the left or the right
      spaced :: Bool,    -- ^ should there be a space between symbol and quantity
      comma :: Bool,     -- ^ should thousands be comma-separated
      precision :: Int   -- ^ number of decimal places to display
    } deriving (Eq,Show,Ord)

data Amount = Amount {
      commodity :: Commodity,
      quantity :: Double,
      price :: Maybe MixedAmount  -- ^ unit price/conversion rate for this amount at posting time
    } deriving (Eq)

newtype MixedAmount = Mixed [Amount] deriving (Eq)

data PostingType = RegularPosting | VirtualPosting | BalancedVirtualPosting
                   deriving (Eq,Show)

data Posting = Posting {
      pstatus :: Bool,
      paccount :: AccountName,
      pamount :: MixedAmount,
      pcomment :: String,
      ptype :: PostingType
    } deriving (Eq)

data ModifierTransaction = ModifierTransaction {
      mtvalueexpr :: String,
      mtpostings :: [Posting]
    } deriving (Eq)

data PeriodicTransaction = PeriodicTransaction {
      ptperiodicexpr :: String,
      ptpostings :: [Posting]
    } deriving (Eq)

data Transaction = Transaction {
      tdate :: Day,
      teffectivedate :: Maybe Day,
      tstatus :: Bool,
      tcode :: String,
      tdescription :: String,
      tcomment :: String,
      tpostings :: [Posting],
      tpreceding_comment_lines :: String
    } deriving (Eq)

data TimeLogCode = SetBalance | SetRequiredHours | In | Out | FinalOut deriving (Eq,Ord) 

data TimeLogEntry = TimeLogEntry {
      tlcode :: TimeLogCode,
      tldatetime :: LocalTime,
      tlcomment :: String
    } deriving (Eq,Ord)

data HistoricalPrice = HistoricalPrice {
      hdate :: Day,
      hsymbol :: String,
      hamount :: MixedAmount
    } deriving (Eq) -- & Show (in Amount.hs)

data Journal = Journal {
      jmodifiertxns :: [ModifierTransaction],
      jperiodictxns :: [PeriodicTransaction],
      jtxns :: [Transaction],
      open_timelog_entries :: [TimeLogEntry],
      historical_prices :: [HistoricalPrice],
      final_comment_lines :: String,
      filepath :: FilePath,
      filereadtime :: ClockTime
    } deriving (Eq)

-- | A generic, pure specification of how to filter raw ledger transactions.
data FilterSpec = FilterSpec {
     datespan  :: DateSpan   -- ^ only include transactions in this date span
    ,cleared   :: Maybe Bool -- ^ only include if cleared\/uncleared\/don't care
    ,real      :: Bool       -- ^ only include if real\/don't care
    ,costbasis :: Bool       -- ^ convert all amounts to cost basis
    ,acctpats  :: [String]   -- ^ only include if matching these account patterns
    ,descpats  :: [String]   -- ^ only include if matching these description patterns
    ,whichdate :: WhichDate  -- ^ which dates to use (transaction or effective)
    }

data LedgerPosting = LedgerPosting {
      lptnum :: Int,              -- ^ internal transaction reference number
      lpstatus :: Bool,           -- ^ posting status
      lpdate :: Day,              -- ^ transaction date
      lpdescription :: String,    -- ^ ledger transaction description
      lpaccount :: AccountName,   -- ^ posting account
      lpamount :: MixedAmount,    -- ^ posting amount
      lptype :: PostingType       -- ^ posting type
    } deriving (Eq)

data Account = Account {
      aname :: AccountName,
      apostings :: [LedgerPosting], -- ^ transactions in this account
      abalance :: MixedAmount         -- ^ sum of transactions in this account and subaccounts
    }

data Ledger = Ledger {
      journaltext :: String,
      journal :: Journal,
      accountnametree :: Tree AccountName,
      accountmap :: Map.Map AccountName Account
    } deriving Typeable

