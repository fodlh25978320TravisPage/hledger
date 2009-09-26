{-|

Generate balances pie chart

-}

module Commands.Chart
where
import Ledger.Utils
import Ledger.Types
import Ledger.Amount
import Ledger.AccountName
import Ledger.Transaction
import Ledger.Ledger
import Ledger.Commodity
import Options

import Graphics.Rendering.Chart
import Data.Colour
import Data.Colour.Names
import Data.List

-- | Generate an image with the pie chart and write it to a file
chart :: [Opt] -> [String] -> Ledger -> IO ()
chart opts args l = renderableToPNGFile (toRenderable chart) w h filename
    where
      chart = genPie opts args l
      filename = getOption opts ChartOutput "hledger.png"
      (w,h) = parseSize $ getOption opts ChartSize "1024x1024"

-- | Extract string option value from a list of options or use the default
getOption :: [Opt] -> (String->Opt) -> String -> String
getOption opts opt def = 
    case reverse $ optValuesForConstructor opt opts of
        [] -> def
        x:_ -> x

-- | Parse image size from a command-line option
parseSize :: String -> (Int,Int)
parseSize str = (read w, read h)
    where
    x = fromMaybe (error "Size should be in WIDTHxHEIGHT format") $ findIndex (=='x') str
    (w,_:h) = splitAt x str

-- | Generate pie chart
genPie :: [Opt] -> [String] -> Ledger -> PieLayout
genPie opts _ l = defaultPieLayout
    { pie_background_ = solidFillStyle $ opaque $ white
    , pie_plot_ = pie_chart }
    where
      pie_chart = defaultPieChart { pie_data_ = items }
      items = mapMaybe (uncurry accountPieItem) $
              flatten $
              balances $
              ledgerAccountTree (depthFromOpts opts) l

-- | Convert all quantities of MixedAccount to a single commodity
amountValue :: MixedAmount -> Double
amountValue = quantity . convertMixedAmountTo unknown

-- | Generate a tree of account names together with their balances.
--   The balance of account is decremented by the balance of its subaccounts
--   which are drawn on the chart.
balances :: Tree Account -> Tree (AccountName, Double)
balances (Node rootAcc subAccs) = Node newroot newsubs
    where
      newroot = (aname rootAcc,
                 amountValue $
                 abalance rootAcc - (sum . map (abalance . root)) subAccs)
      newsubs = map balances subAccs

-- | Build a single pie chart item
accountPieItem :: AccountName -> Double -> Maybe PieItem 
accountPieItem accname balance =
    if balance == 0
        then Nothing 
        else Just $ PieItem accname 0 balance
