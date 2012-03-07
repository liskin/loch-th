-- |
-- Module      : Debug.Trace.LocationTH
-- Copyright   : (c) Tomas Janousek 2011
-- License     : BSD-style
-- Maintainer  : tomi@nomi.cz
-- Stability   : experimental
-- Portability : non-portable (requires Template haskell)
-- Tested      : GHC 7.0.3
--
-- This module provides a Template Haskell based mechanism to tag failures
-- with the location of the failure call. The location message includes the
-- file name, line and column numbers.
-- 

{-# LANGUAGE TemplateHaskell #-}
module Debug.Trace.LocationTH
    ( __LOCATION__
    , assert
    , failure
    , undef
    , check
    , checkIO
    ) where

import qualified Control.Exception as C
import Control.Exception (throw, AssertionFailed(..))
import Language.Haskell.TH.Ppr (pprint)
import Language.Haskell.TH.Syntax (location, Loc(..), Q, Exp, lift)
import System.IO.Unsafe  (unsafePerformIO)
import Text.PrettyPrint.HughesPJ

ppUnless :: Bool -> Doc -> Doc
ppUnless True  _   = empty
ppUnless False doc = doc

-- | Pretty print Loc. Mostly copypasted pprUserSpan from GHC 7.
pprLoc :: Loc -> Doc
pprLoc (Loc { loc_filename = src_path
            , loc_start = (sline, start_col)
            , loc_end = (eline, end_col) })
    | sline == eline = hcat
        [ text src_path <> colon
        , int sline, char ':', int start_col
        , ppUnless (end_col - start_col <= 1)
                   (char '-' <> int (end_col-1))
        ]
    | otherwise = hcat
        [ text src_path <> colon
        , parens (int sline <> char ',' <>  int start_col)
        , char '-'
        , parens (int eline <> char ',' <>
            if end_col == 0 then int end_col else int (end_col-1))
        ]

--
-- | Get the location of current splice as a 'String'.
--
-- @$__LOCATION__ :: 'String'@
--
-- >>> $__LOCATION__ 
-- "<interactive>:1:1-13"
--
__LOCATION__ :: Q Exp
__LOCATION__ = lift =<< (render . pprLoc) `fmap` location

--
-- | If the first argument evaluates to 'True', then the result is the second
-- argument. Otherwise an 'AssertionFailed' exception is raised, containing a
-- 'String' with the source file and line number of the call to 'assert'. 
--
-- @$(assert [| 'False' |]) :: a -> a@
--
-- >>> $(assert [| 5 + 5 == 9 |]) "foo"
-- "*** Exception: <interactive>:1:3-25: Assertion `(5 GHC.Num.+ 5) GHC.Classes.== 9' failed
--
assert :: Q Exp -> Q Exp
assert t = do
    st <- pprint `fmap` t
    [| if' (not $t) $ throw $ AssertionFailed $
        $__LOCATION__ ++ ": Assertion `" ++ st ++ "' failed"
     |]

if' :: Bool -> a -> a -> a
if' True  x _ = x
if' False _ y = y

--
-- | A location-emitting 'error' call.
--
-- @$failure :: 'String' -> a@
--
-- >>> $failure "no such thing."
-- *** Exception: <interactive>:1:1-8: no such thing.
--
failure :: Q Exp
failure = [| error . ($__LOCATION__ ++) . (": " ++) |]

--
-- | A location-emitting 'undefined'.
--
-- @$undef :: a@
--
-- >>> $undef
-- *** Exception: <interactive>:1:1-6: undefined
--
undef :: Q Exp
undef = [| $failure "undefined" |]

--
-- | 'check' wraps a pure, partial function in a location-emitting
-- handler, should an exception be thrown. So instead of producing an
-- anonymous call to 'error', a location will be tagged to the error
-- message.
--
-- @$check :: c -> c@
-- 
-- >>> $check $ head []
-- *** Exception: <interactive>:1:1-6: Prelude.head: empty list
--
-- Be careful with laziness as the argument is only evaluated to weak head
-- normal form:
--
-- >>> $check $ Just $ head ""
-- Just *** Exception: Prelude.head: empty list
-- >>> Just $ $check $ head ""
-- Just *** Exception: <interactive>:9:8-13: Prelude.head: empty list
-- >>> $check $ join deepseq $ Just $ head ""
-- *** Exception: <interactive>:1:1-6: Prelude.head: empty list
--
check :: Q Exp
check = [| unsafePerformIO . $checkIO . C.evaluate |]

--
-- | 'checkIO' wraps an IO function in a location-emitting handler,
-- should an exception be thrown. So instead of producing an anonymous
-- call to 'error', a location will be tagged to the error message.
--
-- @$checkIO :: IO a -> IO a@
--
-- >>> $checkIO $ readFile "/foo"
-- "*** Exception: <interactive>:1:1-8: /foo: openFile: does not exist (No such file or directory)
--
checkIO :: Q Exp
checkIO = [| flip C.catch (return . $failure . showEx) |]

showEx :: C.SomeException -> String
showEx = show
