{-|

A 'Journal' is a parsed ledger file, containing 'Transaction's.
It can be filtered and massaged in various ways, then \"crunched\"
to form a 'Ledger'.

-}

module Ledger.Journal
where
import qualified Data.Map as Map
import Data.Map (findWithDefault, (!))
import System.Time (ClockTime(TOD))
import Ledger.Utils
import Ledger.Types
import Ledger.AccountName
import Ledger.Amount
import Ledger.Transaction (ledgerTransactionWithDate)
import Ledger.Posting
import Ledger.TimeLog


instance Show Journal where
    show j = printf "Journal with %d transactions, %d accounts: %s"
             (length (jtxns j) +
              length (jmodifiertxns j) +
              length (jperiodictxns j))
             (length accounts)
             (show accounts)
             -- ++ (show $ journalTransactions l)
             where accounts = flatten $ journalAccountNameTree j

nulljournal :: Journal
nulljournal = Journal { jmodifiertxns = []
                      , jperiodictxns = []
                      , jtxns = []
                      , open_timelog_entries = []
                      , historical_prices = []
                      , final_comment_lines = []
                      , filepath = ""
                      , filereadtime = TOD 0 0
                      , jtext = ""
                      }

addTransaction :: Transaction -> Journal -> Journal
addTransaction t l0 = l0 { jtxns = t : jtxns l0 }

addModifierTransaction :: ModifierTransaction -> Journal -> Journal
addModifierTransaction mt l0 = l0 { jmodifiertxns = mt : jmodifiertxns l0 }

addPeriodicTransaction :: PeriodicTransaction -> Journal -> Journal
addPeriodicTransaction pt l0 = l0 { jperiodictxns = pt : jperiodictxns l0 }

addHistoricalPrice :: HistoricalPrice -> Journal -> Journal
addHistoricalPrice h l0 = l0 { historical_prices = h : historical_prices l0 }

addTimeLogEntry :: TimeLogEntry -> Journal -> Journal
addTimeLogEntry tle l0 = l0 { open_timelog_entries = tle : open_timelog_entries l0 }

journalPostings :: Journal -> [Posting]
journalPostings = concatMap tpostings . jtxns

journalAccountNamesUsed :: Journal -> [AccountName]
journalAccountNamesUsed = accountNamesFromPostings . journalPostings

journalAccountNames :: Journal -> [AccountName]
journalAccountNames = sort . expandAccountNames . journalAccountNamesUsed

journalAccountNameTree :: Journal -> Tree AccountName
journalAccountNameTree = accountNameTreeFrom . journalAccountNames

-- Various kinds of filtering on journals. We do it differently depending
-- on the command.

-- | Keep only transactions we are interested in, as described by
-- the filter specification. May also massage the data a little.
filterJournalTransactions :: FilterSpec -> Journal -> Journal
filterJournalTransactions FilterSpec{datespan=datespan
                                    ,cleared=cleared
                                    -- ,real=real
                                    -- ,empty=empty
                                    -- ,costbasis=_
                                    ,acctpats=apats
                                    ,descpats=dpats
                                    ,whichdate=whichdate
                                    ,depth=depth
                                    } =
    filterJournalTransactionsByClearedStatus cleared .
    filterJournalPostingsByDepth depth .
    filterJournalTransactionsByAccount apats .
    filterJournalTransactionsByDescription dpats .
    filterJournalTransactionsByDate datespan .
    journalSelectingDate whichdate

-- | Keep only postings we are interested in, as described by
-- the filter specification. May also massage the data a little.
-- This can leave unbalanced transactions.
filterJournalPostings :: FilterSpec -> Journal -> Journal
filterJournalPostings FilterSpec{datespan=datespan
                                ,cleared=cleared
                                ,real=real
                                ,empty=empty
--                                ,costbasis=costbasis
                                ,acctpats=apats
                                ,descpats=dpats
                                ,whichdate=whichdate
                                ,depth=depth
                                } =
    filterJournalPostingsByRealness real .
    filterJournalPostingsByClearedStatus cleared .
    filterJournalPostingsByEmpty empty .
    filterJournalPostingsByDepth depth .
    filterJournalPostingsByAccount apats .
    filterJournalTransactionsByDescription dpats .
    filterJournalTransactionsByDate datespan .
    journalSelectingDate whichdate

-- | Keep only ledger transactions whose description matches the description patterns.
filterJournalTransactionsByDescription :: [String] -> Journal -> Journal
filterJournalTransactionsByDescription pats j@Journal{jtxns=ts} = j{jtxns=filter matchdesc ts}
    where matchdesc = matchpats pats . tdescription

-- | Keep only ledger transactions which fall between begin and end dates.
-- We include transactions on the begin date and exclude transactions on the end
-- date, like ledger.  An empty date string means no restriction.
filterJournalTransactionsByDate :: DateSpan -> Journal -> Journal
filterJournalTransactionsByDate (DateSpan begin end) j@Journal{jtxns=ts} = j{jtxns=filter match ts}
    where match t = maybe True (tdate t>=) begin && maybe True (tdate t<) end

-- | Keep only ledger transactions which have the requested
-- cleared/uncleared status, if there is one.
filterJournalTransactionsByClearedStatus :: Maybe Bool -> Journal -> Journal
filterJournalTransactionsByClearedStatus Nothing j = j
filterJournalTransactionsByClearedStatus (Just val) j@Journal{jtxns=ts} = j{jtxns=filter match ts}
    where match = (==val).tstatus

-- | Keep only postings which have the requested cleared/uncleared status,
-- if there is one.
filterJournalPostingsByClearedStatus :: Maybe Bool -> Journal -> Journal
filterJournalPostingsByClearedStatus Nothing j = j
filterJournalPostingsByClearedStatus (Just c) j@Journal{jtxns=ts} = j{jtxns=map filterpostings ts}
    where filterpostings t@Transaction{tpostings=ps} = t{tpostings=filter ((==c) . postingCleared) ps}

-- | Strip out any virtual postings, if the flag is true, otherwise do
-- no filtering.
filterJournalPostingsByRealness :: Bool -> Journal -> Journal
filterJournalPostingsByRealness False l = l
filterJournalPostingsByRealness True j@Journal{jtxns=ts} = j{jtxns=map filterpostings ts}
    where filterpostings t@Transaction{tpostings=ps} = t{tpostings=filter isReal ps}

-- | Strip out any postings with zero amount, unless the flag is true.
filterJournalPostingsByEmpty :: Bool -> Journal -> Journal
filterJournalPostingsByEmpty True l = l
filterJournalPostingsByEmpty False j@Journal{jtxns=ts} = j{jtxns=map filterpostings ts}
    where filterpostings t@Transaction{tpostings=ps} = t{tpostings=filter (not . isEmptyPosting) ps}

-- | Keep only transactions which affect accounts deeper than the specified depth.
filterJournalTransactionsByDepth :: Maybe Int -> Journal -> Journal
filterJournalTransactionsByDepth Nothing j = j
filterJournalTransactionsByDepth (Just d) j@Journal{jtxns=ts} =
    j{jtxns=(filter (any ((<= d+1) . accountNameLevel . paccount) . tpostings) ts)}

-- | Strip out any postings to accounts deeper than the specified depth
-- (and any ledger transactions which have no postings as a result).
filterJournalPostingsByDepth :: Maybe Int -> Journal -> Journal
filterJournalPostingsByDepth Nothing j = j
filterJournalPostingsByDepth (Just d) j@Journal{jtxns=ts} =
    j{jtxns=filter (not . null . tpostings) $ map filtertxns ts}
    where filtertxns t@Transaction{tpostings=ps} =
              t{tpostings=filter ((<= d) . accountNameLevel . paccount) ps}

-- | Keep only transactions which affect accounts matched by the account patterns.
filterJournalTransactionsByAccount :: [String] -> Journal -> Journal
filterJournalTransactionsByAccount apats j@Journal{jtxns=ts} = j{jtxns=filter match ts}
    where match = any (matchpats apats . paccount) . tpostings

-- | Keep only postings which affect accounts matched by the account patterns.
-- This can leave transactions unbalanced.
filterJournalPostingsByAccount :: [String] -> Journal -> Journal
filterJournalPostingsByAccount apats j@Journal{jtxns=ts} = j{jtxns=map filterpostings ts}
    where filterpostings t@Transaction{tpostings=ps} = t{tpostings=filter (matchpats apats . paccount) ps}

-- | Convert this journal's transactions' primary date to either the
-- actual or effective date.
journalSelectingDate :: WhichDate -> Journal -> Journal
journalSelectingDate ActualDate j = j
journalSelectingDate EffectiveDate j =
    j{jtxns=map (ledgerTransactionWithDate EffectiveDate) $ jtxns j}

-- | Convert all the journal's amounts to their canonical display settings.
-- Ie, in each commodity, amounts will use the display settings of the first
-- amount detected, and the greatest precision of the amounts detected.
-- Also, missing unit prices are added if known from the price history.
-- Also, amounts are converted to cost basis if that flag is active.
-- XXX refactor
canonicaliseAmounts :: Bool -> Journal -> Journal
canonicaliseAmounts costbasis j@Journal{jtxns=ts} = j{jtxns=map fixledgertransaction ts}
    where
      fixledgertransaction (Transaction d ed s c de co ts pr) = Transaction d ed s c de co (map fixrawposting ts) pr
          where
            fixrawposting (Posting s ac a c t txn) = Posting s ac (fixmixedamount a) c t txn
            fixmixedamount (Mixed as) = Mixed $ map fixamount as
            fixamount = (if costbasis then costOfAmount else id) . fixprice . fixcommodity
            fixcommodity a = a{commodity=c} where c = canonicalcommoditymap ! symbol (commodity a)
            canonicalcommoditymap =
                Map.fromList [(s,firstc{precision=maxp}) | s <- commoditysymbols,
                        let cs = commoditymap ! s,
                        let firstc = head cs,
                        let maxp = maximum $ map precision cs
                       ]
            commoditymap = Map.fromList [(s,commoditieswithsymbol s) | s <- commoditysymbols]
            commoditieswithsymbol s = filter ((s==) . symbol) commodities
            commoditysymbols = nub $ map symbol commodities
            commodities = map commodity (concatMap (amounts . pamount) (journalPostings j)
                                         ++ concatMap (amounts . hamount) (historical_prices j))
            fixprice :: Amount -> Amount
            fixprice a@Amount{price=Just _} = a
            fixprice a@Amount{commodity=c} = a{price=journalHistoricalPriceFor j d c}

            -- | Get the price for a commodity on the specified day from the price database, if known.
            -- Does only one lookup step, ie will not look up the price of a price.
            journalHistoricalPriceFor :: Journal -> Day -> Commodity -> Maybe MixedAmount
            journalHistoricalPriceFor j d Commodity{symbol=s} = do
              let ps = reverse $ filter ((<= d).hdate) $ filter ((s==).hsymbol) $ sortBy (comparing hdate) $ historical_prices j
              case ps of (HistoricalPrice{hamount=a}:_) -> Just $ canonicaliseCommodities a
                         _ -> Nothing
                  where
                    canonicaliseCommodities (Mixed as) = Mixed $ map canonicaliseCommodity as
                        where canonicaliseCommodity a@Amount{commodity=Commodity{symbol=s}} =
                                  a{commodity=findWithDefault (error "programmer error: canonicaliseCommodity failed") s canonicalcommoditymap}

-- | Get just the amounts from a ledger, in the order parsed.
journalAmounts :: Journal -> [MixedAmount]
journalAmounts = map pamount . journalPostings

-- | Get just the ammount commodities from a ledger, in the order parsed.
journalCommodities :: Journal -> [Commodity]
journalCommodities = map commodity . concatMap amounts . journalAmounts

-- | Get just the amount precisions from a ledger, in the order parsed.
journalPrecisions :: Journal -> [Int]
journalPrecisions = map precision . journalCommodities

-- | Close any open timelog sessions using the provided current time.
journalConvertTimeLog :: LocalTime -> Journal -> Journal
journalConvertTimeLog t l0 = l0 { jtxns = convertedTimeLog ++ jtxns l0
                                  , open_timelog_entries = []
                                  }
    where convertedTimeLog = entriesFromTimeLogEntries t $ open_timelog_entries l0

-- | The (fully specified) date span containing all the raw ledger's transactions,
-- or DateSpan Nothing Nothing if there are none.
journalDateSpan :: Journal -> DateSpan
journalDateSpan j
    | null ts = DateSpan Nothing Nothing
    | otherwise = DateSpan (Just $ tdate $ head ts) (Just $ addDays 1 $ tdate $ last ts)
    where
      ts = sortBy (comparing tdate) $ jtxns j

-- | Check if a set of ledger account/description patterns matches the
-- given account name or entry description.  Patterns are case-insensitive
-- regular expression strings; those beginning with - are anti-patterns.
matchpats :: [String] -> String -> Bool
matchpats pats str =
    (null positives || any match positives) && (null negatives || not (any match negatives))
    where
      (negatives,positives) = partition isnegativepat pats
      match "" = True
      match pat = containsRegex (abspat pat) str
      negateprefix = "not:"
      isnegativepat = (negateprefix `isPrefixOf`)
      abspat pat = if isnegativepat pat then drop (length negateprefix) pat else pat

-- | Calculate the account tree and account balances from a journal's
-- postings, and return the results for efficient lookup.
crunchJournal :: Journal -> (Tree AccountName, Map.Map AccountName Account)
crunchJournal j = (ant,amap)
    where
      (ant,psof,_,inclbalof) = (groupPostings . journalPostings) j
      amap = Map.fromList [(a, acctinfo a) | a <- flatten ant]
      acctinfo a = Account a (psof a) (inclbalof a)

-- | Given a list of postings, return an account name tree and three query
-- functions that fetch postings, balance, and subaccount-including
-- balance by account name.  This factors out common logic from
-- cacheLedger and summarisePostingsInDateSpan.
groupPostings :: [Posting] -> (Tree AccountName,
                             (AccountName -> [Posting]),
                             (AccountName -> MixedAmount),
                             (AccountName -> MixedAmount))
groupPostings ps = (ant,psof,exclbalof,inclbalof)
    where
      anames = sort $ nub $ map paccount ps
      ant = accountNameTreeFrom $ expandAccountNames anames
      allanames = flatten ant
      pmap = Map.union (postingsByAccount ps) (Map.fromList [(a,[]) | a <- allanames])
      psof = (pmap !)
      balmap = Map.fromList $ flatten $ calculateBalances ant psof
      exclbalof = fst . (balmap !)
      inclbalof = snd . (balmap !)

-- | Add subaccount-excluding and subaccount-including balances to a tree
-- of account names somewhat efficiently, given a function that looks up
-- transactions by account name.
calculateBalances :: Tree AccountName -> (AccountName -> [Posting]) -> Tree (AccountName, (MixedAmount, MixedAmount))
calculateBalances ant psof = addbalances ant
    where
      addbalances (Node a subs) = Node (a,(bal,bal+subsbal)) subs'
          where
            bal         = sumPostings $ psof a
            subsbal     = sum $ map (snd . snd . root) subs'
            subs'       = map addbalances subs

-- | Convert a list of postings to a map from account name to that
-- account's postings.
postingsByAccount :: [Posting] -> Map.Map AccountName [Posting]
postingsByAccount ps = m'
    where
      sortedps = sortBy (comparing paccount) ps
      groupedps = groupBy (\p1 p2 -> paccount p1 == paccount p2) sortedps
      m' = Map.fromList [(paccount $ head g, g) | g <- groupedps]
