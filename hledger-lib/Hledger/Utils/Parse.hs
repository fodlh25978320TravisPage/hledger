{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module Hledger.Utils.Parse (
  SimpleStringParser,
  SimpleTextParser,
  TextParser,

  -- * SourcePos
  SourcePos(..),
  mkPos,
  unPos,
  initialPos,
  sourcePosPretty,
  sourcePosPairPretty,

  choice',
  choiceInState,
  surroundedBy,
  parsewith,
  runTextParser,
  rtp,
  parsewithString,
  parseWithState,
  parseWithState',
  fromparse,
  parseerror,
  showDateParseError,
  nonspace,
  isNewline,
  isNonNewlineSpace,
  restofline,
  eolof,

  spacenonewline,
  skipNonNewlineSpaces,
  skipNonNewlineSpaces1,
  skipNonNewlineSpaces',

  -- ** Trace the state of hledger parsers
  dbgparse,
  traceOrLogParse,

  -- * re-exports
  HledgerParseErrors,
  HledgerParseErrorData,
  customErrorBundlePretty,
)
where

import Control.Monad (when)
import qualified Data.Text as T
import Text.Megaparsec
import Text.Printf
import Control.Monad.State.Strict (StateT, evalStateT)
import Data.Char
import Data.Functor (void)
import Data.Functor.Identity (Identity(..))
import Data.List
import Data.Text (Text)
import Text.Megaparsec.Char
import Text.Megaparsec.Custom
import Hledger.Utils.Debug (debugLevel, traceOrLog)

-- | A parser of string to some type.
type SimpleStringParser a = Parsec HledgerParseErrorData String a

-- | A parser of strict text to some type.
type SimpleTextParser = Parsec HledgerParseErrorData Text  -- XXX an "a" argument breaks the CsvRulesParser declaration somehow

-- | A parser of text that runs in some monad.
type TextParser m a = ParsecT HledgerParseErrorData Text m a

-- class (Stream s, MonadPlus m) => MonadParsec e s m 
-- dbgparse :: (MonadPlus m, MonadParsec e String m) => Int -> String -> m ()

-- | Trace to stderr or log to debug log the provided label (if non-null)
-- and current parser state (position and next input),
-- if the global debug level is at or above the specified level.
-- Uses unsafePerformIO.
dbgparse :: Int -> String -> TextParser m ()
dbgparse level msg = when (level <= debugLevel) $ traceOrLogParse msg

-- | Trace to stderr or log to debug log the provided label (if non-null)
-- and current parser state (position and next input).
-- See also: Hledger.Utils.Debug, megaparsec's dbg.
-- Uses unsafePerformIO.
-- XXX Can be hard to make this evaluate.
traceOrLogParse :: String -> TextParser m ()
traceOrLogParse msg = do
  pos <- getSourcePos
  next <- (T.take peeklength) `fmap` getInput
  let (l,c) = (sourceLine pos, sourceColumn pos)
      s  = printf "at line %2d col %2d: %s" (unPos l) (unPos c) (show next) :: String
      s' = printf ("%-"++show (peeklength+30)++"s") s ++ " " ++ msg
  traceOrLog s' $ return ()
  where
    peeklength = 30

-- | Render a pair of source positions in human-readable form, only displaying the range of lines.
sourcePosPairPretty :: (SourcePos, SourcePos) -> String
sourcePosPairPretty (SourcePos fp l1 _, SourcePos _ l2 c2) =
    fp ++ ":" ++ show (unPos l1) ++ "-" ++ show l2'
  where
    l2' = if unPos c2 == 1 then unPos l2 - 1 else unPos l2  -- might be at end of file with a final new line

-- | Backtracking choice, use this when alternatives share a prefix.
-- Consumes no input if all choices fail.
choice' :: [TextParser m a] -> TextParser m a
choice' = choice . map try

-- | Backtracking choice, use this when alternatives share a prefix.
-- Consumes no input if all choices fail.
choiceInState :: [StateT s (ParsecT HledgerParseErrorData Text m) a] -> StateT s (ParsecT HledgerParseErrorData Text m) a
choiceInState = choice . map try

surroundedBy :: Applicative m => m openclose -> m a -> m a
surroundedBy p = between p p

parsewith :: Parsec e Text a -> Text -> Either (ParseErrorBundle Text e) a
parsewith p = runParser p ""

-- | Run a text parser in the identity monad. See also: parseWithState.
runTextParser, rtp
  :: TextParser Identity a -> Text -> Either HledgerParseErrors a
runTextParser = parsewith
rtp = runTextParser

parsewithString
  :: Parsec e String a -> String -> Either (ParseErrorBundle String e) a
parsewithString p = runParser p ""

-- | Run a stateful parser with some initial state on a text.
-- See also: runTextParser, runJournalParser.
parseWithState
  :: Monad m
  => st
  -> StateT st (ParsecT HledgerParseErrorData Text m) a
  -> Text
  -> m (Either HledgerParseErrors a)
parseWithState ctx p = runParserT (evalStateT p ctx) ""

parseWithState'
  :: (Stream s)
  => st
  -> StateT st (ParsecT e s Identity) a
  -> s
  -> (Either (ParseErrorBundle s e) a)
parseWithState' ctx p = runParser (evalStateT p ctx) ""

fromparse
  :: (Show t, Show (Token t), Show e) => Either (ParseErrorBundle t e) a -> a
fromparse = either parseerror id

parseerror :: (Show t, Show (Token t), Show e) => ParseErrorBundle t e -> a
parseerror e = errorWithoutStackTrace $ showParseError e  -- PARTIAL:

showParseError
  :: (Show t, Show (Token t), Show e)
  => ParseErrorBundle t e -> String
showParseError e = "parse error at " ++ show e

showDateParseError
  :: (Show t, Show (Token t), Show e) => ParseErrorBundle t e -> String
showDateParseError e = printf "date parse error (%s)" (intercalate ", " $ tail $ lines $ show e)

isNewline :: Char -> Bool 
isNewline '\n' = True
isNewline _    = False

nonspace :: TextParser m Char
nonspace = satisfy (not . isSpace)

isNonNewlineSpace :: Char -> Bool
isNonNewlineSpace c = not (isNewline c) && isSpace c

spacenonewline :: (Stream s, Char ~ Token s) => ParsecT HledgerParseErrorData s m Char
spacenonewline = satisfy isNonNewlineSpace
{-# INLINABLE spacenonewline #-}

restofline :: TextParser m String
restofline = anySingle `manyTill` eolof

-- Skip many non-newline spaces.
skipNonNewlineSpaces :: (Stream s, Token s ~ Char) => ParsecT HledgerParseErrorData s m ()
skipNonNewlineSpaces = void $ takeWhileP Nothing isNonNewlineSpace
{-# INLINABLE skipNonNewlineSpaces #-}

-- Skip many non-newline spaces, failing if there are none.
skipNonNewlineSpaces1 :: (Stream s, Token s ~ Char) => ParsecT HledgerParseErrorData s m ()
skipNonNewlineSpaces1 = void $ takeWhile1P Nothing isNonNewlineSpace
{-# INLINABLE skipNonNewlineSpaces1 #-}

-- Skip many non-newline spaces, returning True if any have been skipped.
skipNonNewlineSpaces' :: (Stream s, Token s ~ Char) => ParsecT HledgerParseErrorData s m Bool
skipNonNewlineSpaces' = True <$ skipNonNewlineSpaces1 <|> pure False
{-# INLINABLE skipNonNewlineSpaces' #-}

eolof :: TextParser m ()
eolof = void newline <|> eof
