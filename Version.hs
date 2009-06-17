{-# OPTIONS_GHC -cpp #-}
{-
Version-related utilities.

We should follow http://haskell.org/haskellwiki/Package_versioning_policy .
But currently hledger's version is MAJOR[.MINOR[.BUGFIX]][+PATCHLEVEL].
See also the Makefile.

-}

module Version
where
import System.Info (os, arch)
import Ledger.Utils
import Options (progname)

-- version and PATCHLEVEL are set by the makefile
version       = "0.6.1"

#ifdef PATCHLEVEL
patchlevel = "." ++ show PATCHLEVEL -- must be numeric !
#else
patchlevel = ""
#endif

buildversion  = version ++ patchlevel :: String

binaryfilename = prettify $ splitAtElement '.' buildversion :: String
                where
                  prettify (major:minor:bugfix:patches:[]) =
                      printf "hledger-%s.%s%s%s-%s-%s%s" major minor bugfix' patches' os' arch suffix
                          where
                            bugfix'
                                | bugfix `elem` ["0"{-,"98","99"-}] = ""
                                | otherwise = "."++bugfix
                            patches'
                                | patches/="0" = "+"++patches
                                | otherwise = ""
                            (os',suffix)
                                | os == "darwin"  = ("mac","")
                                | os == "mingw32" = ("windows",".exe")
                                | otherwise       = (os,"")
                  prettify (major:minor:bugfix:[]) = prettify (major:minor:bugfix:"0":[])
                  prettify (major:minor:[])        = prettify (major:minor:"0":"0":[])
                  prettify (major:[])              = prettify (major:"0":"0":"0":[])
                  prettify []                      = error "VERSION is empty, please fix"
                  prettify _                       = error "VERSION has too many components, please fix"

versionstr    = prettify $ splitAtElement '.' buildversion :: String
                where
                  prettify (major:minor:bugfix:patches:[]) =
                      printf "%s.%s%s%s%s" major minor bugfix' patches' desc
                          where
                            bugfix'
                                | bugfix `elem` ["0"{-,"98","99"-}] = ""
                                | otherwise = "."++bugfix
                            patches'
                                | patches/="0" = "+"++patches++" patches"
                                | otherwise = ""
                            desc
--                                 | bugfix=="98" = " (alpha)"
--                                 | bugfix=="99" = " (beta)"
                                | otherwise = ""
                  prettify s = intercalate "." s

versionmsg    = progname ++ "-" ++ versionstr ++ configmsg :: String
    where configmsg
              | null configflags = " with no extras"
              | otherwise = " with " ++ intercalate ", " configflags

configflags   = tail [""
#ifdef VTY
  ,"vty"
#endif
#ifdef HAPPS
  ,"happs"
#endif
 ]
