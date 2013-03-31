---
title: hledger Installation Guide
---

# Installation Guide

hledger works on linux, mac and windows. You can fund ready-to-run
binaries of the latest release - see the [download page](DOWNLOAD.html).

Otherwise, build the latest release from Hackage using cabal-install.
Ensure you have [GHC](http://hackage.haskell.org/ghc/) 7.0 or greater or
the [Haskell Platform](http://hackage.haskell.org/platform/) installed,
then:

    $ cabal update
    $ cabal install hledger

To also install the web interface, do:

    $ cabal install hledger-web

Then try it:

    $ hledger

If you get "hledger not found" or similar, you should add cabal's bin
directory to your PATH environment variable. Eg on unix-like systems,
something like:

    $ echo 'export PATH=$PATH:~/cabal/bin' >> ~/.bash_profile
    $ source ~/.bash_profile

To build the latest [development version](DEVELOPMENT.html) do:

    $ cabal update
    $ darcs get --lazy http://hub.darcs.net/simon/hledger
    $ cd hledger
    $ make install (or do cabal install inside hledger-lib/, hledger/ etc.)

Some add-on packages are available on Hackage:
[hledger-vty](http://hackage.haskell.org/package/hledger-vty),
[hledger-chart](http://hackage.haskell.org/package/hledger-chart),
[hledger-interest](http://hackage.haskell.org/package/hledger-interest).
These are without an active maintainer, and/or platform-specific, so installing them may be harder.

Note: to use non-ascii characters like £, you might need to [configure a suitable locale](MANUAL.html#locale).

### Troubleshooting

There are a lot of ways things can go wrong. Here are
some known issues and things to try. Please also seek
[support](DEVELOPMENT.html#support) from the
[IRC channel](irc://irc.freenode.net/#ledger),
[mail list](http://list.hledger.org) or
[bug tracker](http://bugs.hledger.org).

Starting from the top, consider whether each of these might apply to
you. Tip: blindly reinstalling/upgrading everything in sight probably
won't work, it's better to go in small steps and understand the problem,
or get help.

#. **Did you cabal update ?**  
  If not, `cabal update` and try again.

#. **Do you have a new enough version of GHC ?**  
  Run `ghc --version`. hledger requires GHC 7.0 or greater
  (on [some platforms](#5551), 7.2.1 can be helpful).

#. **Do you have a new enough version of cabal ?**  
  Avoid ancient versions.  `cabal --version` should report at least
  0.10 (and 0.14 is much better). You may be able to upgrade it with:
  
        $ cabal update
        $ cabal install cabal-install-0.14

#. **Are your installed GHC/cabal packages in good repair ?**  
  Run `ghc-pkg check`. If it reports problems, some of your packages have
  become inconsistent, and you should fix these first. 
  [ghc-pkg-clean](https://gist.github.com/1185421) is an easy way.

#. <a name="cabaldeps" />**cabal can't satisfy the new dependencies due to old installed packages**  
  Cabal dependency failures become more likely as you install more
  packages over time. If `cabal install hledger-web --dry` says it can't
  satisfy dependencies, you have this problem. You can:
  
    a. try to understand which packages to remove (with `ghc-pkg unregister`)
       or which constraints to add (with `--constraint 'PKG == ...'`) to help cabal
       find a solution

    b. install into a fresh environment created with
       [virthualenv](http://hackage.haskell.org/package/virthualenv) or
       [cabal-dev](http://hackage.haskell.org/package/cabal-dev)

    c. or (easiest) erase your installed packages with
       [ghc-pkg-reset](https://gist.github.com/1185421) and try again.

#. **Dependency or compilation error in one of the new packages ?**  
   If cabal starts downloading and building packages and then terminates
   with an error, look at the output carefully and identify the problem
   package(s).  If necessary, add `-v2` or `-v3` for more verbose
   output. You can install the new packages one at a time to troubleshoot,
   but remember cabal is smarter when installing all packages at once.

    Often the problem is that you need to install a particular C library
   using your platform's package management system. Or the dependencies
   specified on a package may need updating. Or there may be a compilation
   error.  If you find an error in a hledger package, check the
   [recent commits](http://hub.darcs.net/simon/hledger/changes) to
   see if the [latest development version](#installing) might have a fix.

#. **ExitFailure 11**  
  See
  [http://hackage.haskell.org/trac/hackage/ticket/777](http://hackage.haskell.org/trac/hackage/ticket/777).
  This means that a build process has been killed, usually because it grew
  too large.  This is common on memory-limited VPS's and with GHC 7.4.1.
  Look for some memory-hogging processes you can kill, increase your RAM,
  or limit GHC's heap size by doing `cabal install ... --ghc-options='+RTS
  -M400m'` (400 megabytes works well on my 1G VPS, adjust up or down..)

#. <a name="5551" />**Can't load .so/.DLL for: ncursesw (/usr/lib/libncursesw.so: file too short)**  
  (or similar): cf [GHC bug #5551](http://hackage.haskell.org/trac/ghc/ticket/5551).
  Upgrade GHC to 7.2.1, or try your luck with [this workaround](http://eclipsefp.github.com/faq.html).

#. <a name="iconv" />**Undefined iconv symbols on OS X**  
   This kind of error:

        Linking dist/build/hledger/hledger ...
        Undefined symbols:
          "_iconv_close", referenced from:
              _hs_iconv_close in libHSbase-4.2.0.2.a(iconv.o)
          "_iconv", referenced from:
              _hs_iconv in libHSbase-4.2.0.2.a(iconv.o)
          "_iconv_open", referenced from:
              _hs_iconv_open in libHSbase-4.2.0.2.a(iconv.o)

    probably means you are on a mac with macports libraries installed, cf
    [http://hackage.haskell.org/trac/ghc/ticket/4068](http://hackage.haskell.org/trac/ghc/ticket/4068).
    To work around temporarily, add this --extra-lib-dirs flag:

        $ cabal install hledger --extra-lib-dirs=/usr/lib

    or permanently, add this to ~/.cabal/config:
    
        extra-lib-dirs: /usr/lib

#. **hledger-vty requires curses-related libraries**  
  On Ubuntu, eg, you'll need the `libncurses5-dev` package. On Windows,
  these are not available (unless perhaps via Cygwin.)

#. **hledger-chart requires GTK-related libraries**  
  On Ubuntu, eg, install the `libghc6-gtk-dev` package. See also [Gtk2Hs installation notes](http://code.haskell.org/gtk2hs/INSTALL).

