{-|
An 'Amount' is some quantity of money, shares, or anything else.

A simple amount is a commodity, quantity pair (where commodity can be anything):

@
  $1 
  £-50
  EUR 3.44 
  GOOG 500
  1.5h
  90apples
  0 
@

A mixed amount (not yet implemented) is one or more simple amounts:

@
  $50, EUR 3, AAPL 500
  16h, $13.55, oranges 6
@

Commodities may be convertible or not. A mixed amount containing only
convertible commodities can be converted to a simple amount. Arithmetic
examples:

@
  $1 - $5 = $-4
  $1 + EUR 0.76 = $2
  EUR0.76 + $1 = EUR 1.52
  EUR0.76 - $1 = 0
  ($5, 2h) + $1 = ($6, 2h)
  ($50, EUR 3, AAPL 500) + ($13.55, oranges 6) = $67.51, AAPL 500, oranges 6
  ($50, EUR 3) * $-1 = $-53.96
  ($50, AAPL 500) * $-1 = error
@   
-}

module Ledger.Amount
where
import Ledger.Utils
import Ledger.Types
import Ledger.Commodity


instance Show Amount where show = showAmount

-- | Get the string representation of an amount, based on its commodity's
-- display settings.
showAmount :: Amount -> String
showAmount (Amount (Commodity {symbol=sym,side=side,spaced=spaced,precision=p}) q)
    | side==L = printf "%s%s%s" sym space quantity
    | side==R = printf "%s%s%s" quantity space sym
    where 
      space = if spaced then " " else ""
      quantity = punctuatethousands $ printf ("%."++show p++"f") q

-- | Add thousands-separating commas to a decimal number string
punctuatethousands :: String -> String
punctuatethousands s =
    sign ++ (addcommas int) ++ frac
    where 
      (sign,num) = break isDigit s
      (int,frac) = break (=='.') num
      addcommas = reverse . concat . intersperse "," . triples . reverse
      triples [] = []
      triples l  = [take 3 l] ++ (triples $ drop 3 l)

-- | Get the string representation of an amount, rounded, or showing just "0" if it's zero.
showAmountOrZero :: Amount -> String
showAmountOrZero a
    | isZeroAmount a = "0"
    | otherwise = showAmount a

-- | is this amount zero, when displayed with its given precision ?
isZeroAmount :: Amount -> Bool
isZeroAmount a@(Amount c _ ) = nonzerodigits == ""
    where
      nonzerodigits = filter (flip notElem "-+,.0") quantitystr
      quantitystr = withoutsymbol $ showAmount a
      withoutsymbol = drop (length $ symbol c) -- XXX

instance Num Amount where
    abs (Amount c q) = Amount c (abs q)
    signum (Amount c q) = Amount c (signum q)
    fromInteger i = Amount (comm "") (fromInteger i)
    (+) = amountop (+)
    (-) = amountop (-)
    (*) = amountop (*)

-- | Apply a binary arithmetic operator to two amounts, converting to the
-- second one's commodity and adopting the lowest precision. (Using the
-- second commodity means that folds (like sum [Amount]) will preserve the
-- commodity.)
amountop :: (Double -> Double -> Double) -> Amount -> Amount -> Amount
amountop op a@(Amount ac aq) b@(Amount bc bq) = 
    Amount bc ((quantity $ convertAmountTo bc a) `op` bq)

-- | Convert an amount to the specified commodity using the appropriate
-- exchange rate.
convertAmountTo :: Commodity -> Amount -> Amount
convertAmountTo c2 (Amount c1 q) = Amount c2 (q * conversionRate c1 c2)

-- | Sum a list of amounts. This is still needed because a final zero
-- amount will discard the sum's commodity.
sumAmounts :: [Amount] -> Amount
sumAmounts = sum . filter (not . isZeroAmount)

nullamt = Amount (comm "") 0

-- temporary value for partial entries
autoamt = Amount (Commodity {symbol="AUTO",side=L,spaced=False,comma=False,precision=0,rate=1}) 0
