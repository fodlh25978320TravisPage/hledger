{-|

'AccountName's are strings like @assets:cash:petty@.
From a set of these we derive the account hierarchy.

-}

module Ledger.AccountName
where
import Ledger.Utils
import Ledger.Types


sepchar = ':'

accountNameComponents :: AccountName -> [String]
accountNameComponents = splitAtElement sepchar

accountNameFromComponents :: [String] -> AccountName
accountNameFromComponents = concat . intersperse [sepchar]

accountLeafName :: AccountName -> String
accountLeafName = last . accountNameComponents

accountNameLevel :: AccountName -> Int
accountNameLevel "" = 0
accountNameLevel a = (length $ filter (==sepchar) a) + 1

-- | ["a:b:c","d:e"] -> ["a","a:b","a:b:c","d","d:e"]
expandAccountNames :: [AccountName] -> [AccountName]
expandAccountNames as = nub $ concat $ map expand as
    where expand as = map accountNameFromComponents (tail $ inits $ accountNameComponents as)

-- | ["a:b:c","d:e"] -> ["a","d"]
topAccountNames :: [AccountName] -> [AccountName]
topAccountNames as = [a | a <- expandAccountNames as, accountNameLevel a == 1]

parentAccountName :: AccountName -> AccountName
parentAccountName a = accountNameFromComponents $ init $ accountNameComponents a

parentAccountNames :: AccountName -> [AccountName]
parentAccountNames a = parentAccountNames' $ parentAccountName a
    where
      parentAccountNames' "" = []
      parentAccountNames' a = [a] ++ (parentAccountNames' $ parentAccountName a)

isAccountNamePrefixOf :: AccountName -> AccountName -> Bool
p `isAccountNamePrefixOf` s = ((p ++ [sepchar]) `isPrefixOf` s)

isSubAccountNameOf :: AccountName -> AccountName -> Bool
s `isSubAccountNameOf` p = 
    (p `isAccountNamePrefixOf` s) && (accountNameLevel s == (accountNameLevel p + 1))

subAccountNamesFrom :: [AccountName] -> AccountName -> [AccountName]
subAccountNamesFrom accts a = filter (`isSubAccountNameOf` a) accts

-- | We could almost get by with just the AccountName manipulations
-- above, but we need smarter structures to eg display the account
-- tree with boring accounts elided.  This converts a list of
-- AccountName to a tree (later we will convert that to a tree of
-- 'Account'.)
accountNameTreeFrom_props =
    [
     accountNameTreeFrom ["a"]       == Node "top" [Node "a" []],
     accountNameTreeFrom ["a","b"]   == Node "top" [Node "a" [], Node "b" []],
     accountNameTreeFrom ["a","a:b"] == Node "top" [Node "a" [Node "a:b" []]],
     accountNameTreeFrom ["a:b"]     == Node "top" [Node "a" [Node "a:b" []]]
    ]
accountNameTreeFrom :: [AccountName] -> Tree AccountName
accountNameTreeFrom accts = 
    Node "top" (accountsFrom (topAccountNames accts))
        where
          accountsFrom :: [AccountName] -> [Tree AccountName]
          accountsFrom [] = []
          accountsFrom as = [Node a (accountsFrom $ subs a) | a <- as]
          subs = (subAccountNamesFrom accts)

-- | Elide an account name to fit in the specified width.
-- From the ledger 2.6 news:
-- 
-- @
--   What Ledger now does is that if an account name is too long, it will
--   start abbreviating the first parts of the account name down to two
--   letters in length.  If this results in a string that is still too
--   long, the front will be elided -- not the end.  For example:
--
--     Expenses:Cash           ; OK, not too long
--     Ex:Wednesday:Cash       ; "Expenses" was abbreviated to fit
--     Ex:We:Afternoon:Cash    ; "Expenses" and "Wednesday" abbreviated
--     ; Expenses:Wednesday:Afternoon:Lunch:Snack:Candy:Chocolate:Cash
--     ..:Af:Lu:Sn:Ca:Ch:Cash  ; Abbreviated and elided!
-- @
elideAccountName :: Int -> AccountName -> AccountName
elideAccountName width s = 
    elideLeft width $ accountNameFromComponents $ elideparts width [] $ accountNameComponents s
      where
        elideparts :: Int -> [String] -> [String] -> [String]
        elideparts width done ss
          | (length $ accountNameFromComponents $ done++ss) <= width = done++ss
          | length ss > 1 = elideparts width (done++[take 2 $ head ss]) (tail ss)
          | otherwise = done++ss


-- -- | Check if a set of ledger account/description patterns matches the
-- -- given account name or entry description.  Patterns are case-insensitive
-- -- regular expression strings; those beginning with - are anti-patterns.
-- -- 
-- -- Call with forbalancereport=True to mimic ledger's balance report
-- -- matching. Account patterns usually match the full account name, but in
-- -- balance reports when the pattern does not contain : and is not an
-- -- anti-pattern, it matches only the leaf name.
-- matchpats :: Bool -> [String] -> String -> Bool
-- matchpats forbalancereport pats str =
--     (null positives || any ismatch positives) && (null negatives || not (any ismatch negatives))
--     where 
--       isnegative = (== negativepatternchar) . head
--       (negatives,positives) = partition isnegative pats
--       ismatch pat = containsRegex (mkRegexWithOpts pat' True True) matchee
--           where 
--             pat' = if isnegative pat then drop 1 pat else pat
--             matchee = if forbalancereport && not (':' `elem` pat) && not (isnegative pat)
--                       then accountLeafName str
--                       else str

-- | Check if a set of ledger account/description patterns matches the
-- given account name or entry description.  Patterns are case-insensitive
-- regular expression strings; those beginning with - are anti-patterns.
matchpats :: [String] -> String -> Bool
matchpats pats str =
    (null positives || any match positives) && (null negatives || not (any match negatives))
    where
      (negatives,positives) = partition isnegativepat pats
      match "" = True
      match pat = matchregex (abspat pat) str

-- | Similar to matchpats, but follows the special behaviour of ledger
-- 2.6's balance command: positive patterns which do not contain : match
-- the account leaf name, other patterns match the full account name.
matchpats_balance :: [String] -> String -> Bool
matchpats_balance pats str = match_positive_pats pats str && (not $ match_negative_pats pats str)
--    (null positives || any match positives) && (null negatives || not (any match negatives))
--     where
--       (negatives,positives) = partition isnegativepat pats
--       match "" = True
--       match pat = matchregex (abspat pat) matchee
--           where 
--             matchee = if not (':' `elem` pat) && not (isnegativepat pat)
--                       then accountLeafName str
--                       else str

-- | Do the positives in these patterns permit a match for this string ?
match_positive_pats :: [String] -> String -> Bool
match_positive_pats pats str = (null ps) || (any match ps)
    where
      ps = positivepats pats
      match "" = True
      match p = matchregex (abspat p) matchee
          where 
            matchee | ':' `elem` p = str
                    | otherwise = accountLeafName str

-- | Do the negatives in these patterns prevent a match for this string ?
match_negative_pats :: [String] -> String -> Bool
match_negative_pats pats str = (not $ null ns) && (any match ns)
    where
      ns = map abspat $ negativepats pats
      match "" = True
      match p = matchregex (abspat p) str

negativepatternchar = '-'
isnegativepat pat = (== [negativepatternchar]) $ take 1 pat
abspat pat = if isnegativepat pat then drop 1 pat else pat
positivepats = filter (not . isnegativepat)
negativepats = filter isnegativepat
matchregex pat str = containsRegex (mkRegexWithOpts pat True True) str

