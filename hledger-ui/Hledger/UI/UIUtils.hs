{-# LANGUAGE CPP #-}
{- | Rendering & misc. helpers. -}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE CPP #-}

module Hledger.UI.UIUtils
where

import Brick
import Brick.Widgets.Border
import Brick.Widgets.Border.Style
-- import Brick.Widgets.Center
import Brick.Widgets.Dialog
import Brick.Widgets.Edit
import Brick.Widgets.List
import Control.Monad.IO.Class
import Data.List
import Data.Maybe
#if !(MIN_VERSION_base(4,11,0))
import Data.Monoid
#endif
import Graphics.Vty (Event(..),Key(..),Modifier(..),Color,Attr,currentAttr)
import Lens.Micro.Platform
import System.Environment

import Hledger hiding (Color)
import Hledger.Cli (CliOpts(rawopts_))
import Hledger.Cli.DocFiles
import Hledger.UI.UITypes
import Hledger.UI.UIState


-- ui

-- | Draw the help dialog, called when help mode is active.
helpDialog :: CliOpts -> Widget Name
helpDialog copts =
  Widget Fixed Fixed $ do
    c <- getContext
    render $
      renderDialog (dialog (Just "Help (?/LEFT/ESC to close)") Nothing (c^.availWidthL)) $ -- (Just (0,[("ok",())]))
      padTopBottom 1 $ padLeftRight 1 $
        vBox [
           hBox [
              padLeftRight 1 $
                vBox [
                   str "NAVIGATION"
                  ,renderKey ("UP/DOWN/PGUP/PGDN/HOME/END", "")
                  ,str "  move selection"
                  ,renderKey ("RIGHT", "more detail")
                  ,renderKey ("LEFT", "previous screen")
                  ,str "  (or vi/emacs movement keys)"
                  ,renderKey ("ESC", "cancel / reset to top")
                  ,str " "
                  ,str "MISC"
                  ,renderKey ("?", "toggle help")
                  ,renderKey ("a", "add transaction (hledger add)")
                  ,renderKey ("A", "add transaction (hledger-iadd)")
                  ,renderKey ("E", "open editor")
                  ,renderKey ("I", "toggle balance assertions")
                  ,renderKey ("CTRL-l", "redraw & recenter")
                  ,renderKey ("g", "reload data")
                  ,renderKey ("q", "quit")
                  ,str " "
                  ,str "MANUAL"
                  ,str "choose format:"
                  ,renderKey ("p", "pager")
                  ,renderKey ("m", "man")
                  ,renderKey ("i", "info")
                ]
             ,padLeftRight 1 $
                vBox [
                   str "FILTERING"
                  ,renderKey ("SHIFT-DOWN/UP", "shrink/grow report period")
                  ,renderKey ("SHIFT-RIGHT/LEFT", "next/previous report period")
                  ,renderKey ("t", "set report period to today")
                  ,str " "
                  ,renderKey ("/", "set a filter query")
                  ,renderKey ("U", 
                    ["toggle unmarked/all"
                    ,"cycle unmarked/not unmarked/all"
                    ,"toggle unmarked filter"
                    ] !! (statusstyle-1))
                  ,renderKey ("P",
                    ["toggle pending/all"
                    ,"cycle pending/not pending/all"
                    ,"toggle pending filter"
                    ] !! (statusstyle-1))
                  ,renderKey ("C",
                    ["toggle cleared/all"
                    ,"cycle cleared/not cleared/all"
                    ,"toggle cleared filter"
                    ] !! (statusstyle-1))
                  ,renderKey ("R", "toggle real/all")
                  ,renderKey ("Z", "toggle nonzero/all")
                  ,renderKey ("DEL/BS", "remove filters")
                  ,str " "
                  ,str "accounts screen:"
                  ,renderKey ("-+0123456789", "set depth limit")
                  ,renderKey ("H", "toggle period balance (shows change) or\nhistorical balance (includes older postings)")
                  ,renderKey ("T", "toggle tree (amounts include subaccounts) or\nflat mode (amounts exclude subaccounts\nexcept at depth limit)")
                  ,str " "
                  ,str "register screen:"
                  ,renderKey ("H", "toggle period or historical total")
                  ,renderKey ("T", "toggle inclusion of subaccount transactions\n(and tree/flat mode on accounts screen)")
                ]
             ]
--           ,vBox [
--              str " "
--             ,hCenter $ padLeftRight 1 $
--               hCenter (str "MANUAL")
--               <=>
--               hCenter (hBox [
--                  renderKey ("t", "text")
--                 ,str " "
--                 ,renderKey ("m", "man page")
--                 ,str " "
--                 ,renderKey ("i", "info")
--                 ])
--             ]
          ]
  where
    renderKey (key,desc) = withAttr (borderAttr <> "keys") (str key) <+> str " " <+> str desc
    statusstyle = min 3 $ fromMaybe 1 $ maybeintopt "status-toggles" $ rawopts_ copts 

-- | Event handler used when help mode is active.
-- May invoke $PAGER, less, man or info, which is likely to fail on MS Windows, TODO.
helpHandle :: UIState -> BrickEvent Name AppEvent -> EventM Name (Next UIState)
helpHandle ui ev = do
  pagerprog <- liftIO $ fromMaybe "less" <$> lookupEnv "PAGER"
  case ev of
    VtyEvent e | e `elem` (moveLeftEvents ++ [EvKey KEsc [], EvKey (KChar '?') []]) -> continue $ setMode Normal ui
    VtyEvent (EvKey (KChar 'p') []) -> suspendAndResume $ runPagerForTopic pagerprog "hledger-ui" >> return ui'
    VtyEvent (EvKey (KChar 'm') []) -> suspendAndResume $ runManForTopic             "hledger-ui" >> return ui'
    VtyEvent (EvKey (KChar 'i') []) -> suspendAndResume $ runInfoForTopic            "hledger-ui" >> return ui'
    _ -> continue ui
  where
    ui' = setMode Normal ui

-- | Draw the minibuffer.
minibuffer :: Editor String Name -> Widget Name
minibuffer ed =
  forceAttr (borderAttr <> "minibuffer") $
  hBox $
#if MIN_VERSION_brick(0,19,0)
  [txt "filter: ", renderEditor (str . unlines) True ed]
#else
  [txt "filter: ", renderEditor True ed]
#endif

-- | Wrap a widget in the default hledger-ui screen layout.
defaultLayout :: Widget Name -> Widget Name -> Widget Name -> Widget Name
defaultLayout toplabel bottomlabel =
  topBottomBorderWithLabels (str " "<+>toplabel<+>str " ") (str " "<+>bottomlabel<+>str " ") .
  margin 1 0 Nothing
  -- topBottomBorderWithLabel2 label .
  -- padLeftRight 1 -- XXX should reduce inner widget's width by 2, but doesn't
                    -- "the layout adjusts... if you use the core combinators"

borderQueryStr :: String -> Widget Name
borderQueryStr ""  = str ""
borderQueryStr qry = str " matching " <+> withAttr (borderAttr <> "query") (str qry)

borderDepthStr :: Maybe Int -> Widget Name
borderDepthStr Nothing  = str ""
borderDepthStr (Just d) = str " to " <+> withAttr (borderAttr <> "query") (str $ "depth "++show d)

borderPeriodStr :: String -> Period -> Widget Name
borderPeriodStr _           PeriodAll = str ""
borderPeriodStr preposition p         = str (" "++preposition++" ") <+> withAttr (borderAttr <> "query") (str $ showPeriod p)

borderKeysStr :: [(String,String)] -> Widget Name
borderKeysStr = borderKeysStr' . map (\(a,b) -> (a, str b))

borderKeysStr' :: [(String,Widget Name)] -> Widget Name
borderKeysStr' keydescs =
  hBox $
  intersperse sep $
  [withAttr (borderAttr <> "keys") (str keys) <+> str ":" <+> desc | (keys, desc) <- keydescs]
  where
    -- sep = str " | "
    sep = str " "

-- temporary shenanigans:

-- | Convert the special account name "*" (from balance report with depth limit 0) to something clearer.
replaceHiddenAccountsNameWith :: AccountName -> AccountName -> AccountName
replaceHiddenAccountsNameWith anew a | a == hiddenAccountsName = anew
                                     | a == "*"                = anew
                                     | otherwise               = a

hiddenAccountsName = "..." -- for now

-- generic

topBottomBorderWithLabel :: Widget Name -> Widget Name -> Widget Name
topBottomBorderWithLabel label = \wrapped ->
  Widget Greedy Greedy $ do
    c <- getContext
    let (_w,h) = (c^.availWidthL, c^.availHeightL)
        h' = h - 2
        wrapped' = vLimit (h') wrapped
        debugmsg =
          ""
          -- "  debug: "++show (_w,h')
    render $
      hBorderWithLabel (label <+> str debugmsg)
      <=>
      wrapped'
      <=>
      hBorder

topBottomBorderWithLabels :: Widget Name -> Widget Name -> Widget Name -> Widget Name
topBottomBorderWithLabels toplabel bottomlabel = \wrapped ->
  Widget Greedy Greedy $ do
    c <- getContext
    let (_w,h) = (c^.availWidthL, c^.availHeightL)
        h' = h - 2
        wrapped' = vLimit (h') wrapped
        debugmsg =
          ""
          -- "  debug: "++show (_w,h')
    render $
      hBorderWithLabel (toplabel <+> str debugmsg)
      <=>
      wrapped'
      <=>
      hBorderWithLabel bottomlabel

-- XXX should be equivalent to the above, but isn't (page down goes offscreen)
_topBottomBorderWithLabel2 :: Widget Name -> Widget Name -> Widget Name
_topBottomBorderWithLabel2 label = \wrapped ->
 let debugmsg = ""
 in hBorderWithLabel (label <+> str debugmsg)
    <=>
    wrapped
    <=>
    hBorder

-- XXX superseded by pad, in theory
-- | Wrap a widget in a margin with the given horizontal and vertical
-- thickness, using the current background colour or the specified
-- colour.
-- XXX May disrupt border style of inner widgets.
-- XXX Should reduce the available size visible to inner widget, but doesn't seem to (cf rsDraw2).
margin :: Int -> Int -> Maybe Color -> Widget Name -> Widget Name
margin h v mcolour = \w ->
  Widget Greedy Greedy $ do
    c <- getContext
    let w' = vLimit (c^.availHeightL - v*2) $ hLimit (c^.availWidthL - h*2) w
        attr = maybe currentAttr (\c -> c `on` c) mcolour
    render $
      withBorderAttr attr $
      withBorderStyle (borderStyleFromChar ' ') $
      applyN v (hBorder <=>) $
      applyN h (vBorder <+>) $
      applyN v (<=> hBorder) $
      applyN h (<+> vBorder) $
      w'

   -- withBorderAttr attr .
   -- withBorderStyle (borderStyleFromChar ' ') .
   -- applyN n border

withBorderAttr :: Attr -> Widget Name -> Widget Name
withBorderAttr attr = updateAttrMap (applyAttrMappings [(borderAttr, attr)])

-- | Like brick's continue, but first run some action to modify brick's state.
-- This action does not affect the app state, but might eg adjust a widget's scroll position.
continueWith :: EventM n () -> ui -> EventM n (Next ui)
continueWith brickaction ui = brickaction >> continue ui

-- | Scroll a list's viewport so that the selected item is centered in the
-- middle of the display area.
scrollToTop :: List Name e -> EventM Name ()
scrollToTop list = do
  let vpname = list^.listNameL
  setTop (viewportScroll vpname) 0 

-- | Scroll a list's viewport so that the selected item is centered in the
-- middle of the display area.
scrollSelectionToMiddle :: List Name e -> EventM Name ()
scrollSelectionToMiddle list = do
  let mselectedrow = list^.listSelectedL 
      vpname = list^.listNameL
  mvp <- lookupViewport vpname
  case (mselectedrow, mvp) of
    (Just selectedrow, Just vp) -> do
      let
        itemheight   = dbg4 "itemheight" $ list^.listItemHeightL
        vpheight     = dbg4 "vpheight" $ vp^.vpSize._2
        itemsperpage = dbg4 "itemsperpage" $ vpheight `div` itemheight
        toprow       = dbg4 "toprow" $ max 0 (selectedrow - (itemsperpage `div` 2)) -- assuming ViewportScroll's row offset is measured in list items not screen rows
      setTop (viewportScroll vpname) toprow 
    _ -> return ()

--                 arrow keys       vi keys               emacs keys
moveUpEvents    = [EvKey KUp []   , EvKey (KChar 'k') [], EvKey (KChar 'p') [MCtrl]]
moveDownEvents  = [EvKey KDown [] , EvKey (KChar 'j') [], EvKey (KChar 'n') [MCtrl]]
moveLeftEvents  = [EvKey KLeft [] , EvKey (KChar 'h') [], EvKey (KChar 'b') [MCtrl]]
moveRightEvents = [EvKey KRight [], EvKey (KChar 'l') [], EvKey (KChar 'f') [MCtrl]]

normaliseMovementKeys ev
  | ev `elem` moveUpEvents    = EvKey KUp []
  | ev `elem` moveDownEvents  = EvKey KDown []
  | ev `elem` moveLeftEvents  = EvKey KLeft []
  | ev `elem` moveRightEvents = EvKey KRight []
  | otherwise = ev
