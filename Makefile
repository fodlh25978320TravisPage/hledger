# hledger project makefile

# ghc 6.12 executables need a locale
export LANG=en_US.UTF-8

# command line to run during "make prof" and "make heap"
PROFCMD=bin/hledgerp -f data/1000x1000x10.journal balance >/dev/null

# command to run during "make coverage"
COVCMD=test

# executables to run during "make simplebench". They should be on the path
# or in the current directory. hledger executables for benchmarking should
# generally be the standard optimised cabal build, constrained to parsec 2.
BENCHEXES=hledger-0.9 hledger-0.10-1 hledger-0.11 hledger-0.12.1 hledgeropt ledger
#BENCHEXES=hledger

# misc. tools
#VIEWHTML=open -a 'Google Chrome'
VIEWHTML=google-chrome
VIEWPS=google-chrome
VIEWPDF=google-chrome
PRINT=lpr

PACKAGES=\
	hledger-lib \
	hledger \
	hledger-web \
	hledger-vty \
	hledger-chart
INCLUDEPATHS=\
	-ihledger-lib \
	-ihledger \
	-ihledger-web \
	-ihledger-vty \
	-ihledger-chart
MAIN=hledger/hledger.hs
# all source files in the project (plus a few strays like Setup.hs & hlint.hs)
SOURCEFILES:= \
	hledger/*hs \
	hledger/Hledger/*/*hs \
	hledger-*/*hs \
	hledger-*/Hledger/*hs \
	hledger-*/Hledger/*/*hs
# a more careful list suitable for for haddock
SOURCEFILESFORHADDOCK:= \
	hledger-lib/Hledger/*hs \
	hledger-lib/Hledger/*/*hs \
	hledger/Hledger/Cli/*hs \
	hledger-web/Hledger/*/*hs \
	hledger-vty/Hledger/*/*hs \
	hledger-chart/Hledger/*/*hs
VERSIONHS=hledger/Hledger/Cli/Version.hs
CABALFILES:= \
	hledger/hledger.cabal \
	hledger-*/*.cabal
# DOCFILES:=README DOWNLOAD MANUAL DEVELOPMENT NEWS SCREENSHOTS CONTRIBUTORS
BINARYFILENAME=$(shell touch $(VERSIONHS); runhaskell -ihledger $(MAIN) --binary-filename)
PATCHLEVEL:=$(shell expr `darcs changes --count --from-tag=\\\\\.` - 1)
WARNINGS:=-W -fwarn-tabs #-fwarn-orphans -fwarn-simple-patterns -fwarn-monomorphism-restriction -fwarn-name-shadowing
DEFINEFLAGS:=
PREFERMACUSRLIBFLAGS=-L/usr/lib
BUILDFLAGS:=-DMAKE $(WARNINGS) $(INCLUDEPATHS) $(PREFERMACUSRLIBFLAGS) -DPATCHLEVEL=$(PATCHLEVEL)
LINUXRELEASEBUILDFLAGS:=-DMAKE $(WARNINGS) $(INCLUDEPATHS) -O2 -static -optl-static -optl-pthread
MACRELEASEBUILDFLAGS:=-DMAKE $(WARNINGS) $(INCLUDEPATHS) $(PREFERMACUSRLIBFLAGS) #-O2 # -optl-L/usr/lib
#WINDOWSRELEASEBUILDFLAGS:=-DMAKE $(WARNINGS) $(INCLUDEPATHS)
TIME:=$(shell date +"%Y%m%d%H%M")

# file defining the current release version
VERSIONFILE=VERSION
# two or three-part version string, whatever's in VERSION
VERSION:=$(shell grep -v '^--' $(VERSIONFILE))
# three-part version string, 0-padded if necessary
ifeq ($(shell ghc -e "length (filter (=='.') \"$(VERSION)\")"), 1)
VERSION3:=$(VERSION).0
else
VERSION3:=$(VERSION)
endif
# files which should be updated when the version changes
VERSIONSENSITIVEFILES=\
	$(VERSIONHS) \
	MANUAL.markdown \
	DOWNLOAD.markdown \
	$(CABALFILES) \
	hledger-web/.hledger/web/.version \

default: tag hledger

######################################################################
# BUILDING

# set version numbers, fetch dependencies, build and install standard binaries
# and libs from all hledger packages. A good thing to run first; the other
# allcabal rules require hledger-VERSION and hledger-lib-VERSION installed.
# You may want to change the version number in VERSION file first.
install: allcabalinstall

# set version numbers and configure all hledger packages
configure: allcabalconfigure

# set version numbers and build all hledger packages
build: allcabalbuild

# set version numbers and cabal test all hledger packages
cabaltest: allcabaltest

# run a cabal command in all hledger package dirs
allcabal%:
	for p in $(PACKAGES); do (echo doing cabal $* in $$p; cd $$p; cabal $*); done

# run a command in all hledger package dirs
all%:
	for p in $(PACKAGES); do (echo doing $* in $$p; cd $$p; $*); done

# auto-recompile and run (something, eg unit tests) whenever a module changes.
# sp is from searchpath.org, you might need the http://joyful.com/repos/searchpath version.
autotest:
	rm -f bin/hledger
	sp --no-exts --no-default-map -o bin/hledger ghc --make $(MAIN) -ihledger $(BUILDFLAGS) --run test

# as above for add-on programs
autoweb: linkhledgerwebdir
	rm -f bin/hledger-web
	sp --no-exts --no-default-map -o bin/hledger-web ghc --make hledger-web/hledger-web.hs -ihledger-web -ihledger $(BUILDFLAGS) --run --debug -B

autovty:
	rm -f bin/hledger-vty
	sp --no-exts --no-default-map -o bin/hledger-vty ghc --make hledger-vty/hledger-vty.hs -ihledger-vty -ihledger $(BUILDFLAGS) --run --help

autochart:
	rm -f bin/hledger-chart
	sp --no-exts --no-default-map -o bin/hledger-chart ghc --make hledger-chart/hledger-chart.hs -ihledger-chart -ihledger $(BUILDFLAGS) --run --help

# make symlinks so that running hledger-web from the top directory will
# use the in-development hledger-web support files. Cf Hledger.Web.Settings:
HLEDGERDATADIR:=.hledger
linkhledgerwebdir:
	mkdir -p $(HLEDGERDATADIR); ln -sf ../hledger-web/$(HLEDGERDATADIR)/web $(HLEDGERDATADIR)/web

# build the standalone unit test runner. Requires test-framework, which
# may not work on windows.
tools/unittest: tools/unittest.hs
	ghc --make -threaded -O2 tools/unittest.hs

# build the doctest runner
tools/doctest: tools/doctest.hs
	ghc --make tools/doctest.hs

# build the simple benchmark runner. Requires tabular.
tools/simplebench: tools/simplebench.hs
	ghc --make tools/simplebench.hs

# build the criterion-based benchmark runner. Requires criterion.
tools/criterionbench: tools/criterionbench.hs
	ghc --make tools/criterionbench.hs

# build the progression-based benchmark runner. Requires progression.
tools/progressionbench: tools/progressionbench.hs
	ghc --make tools/progressionbench.hs

# build the generatejournal tool
tools/generatejournal: tools/generatejournal.hs
	ghc --make tools/generatejournal.hs

######################################################################
# TESTING


######################################################################
# DOCUMENTATION


######################################################################
# RELEASING


######################################################################
# MISCELLANEOUS



######################################################################
# OLD PRE PKG SPLIT
######################################################################

######################################################################
# BUILDING

hledgerall: hledger hledger-web hledger-vty hledger-chart

# build developer binaries, as quickly as possible
bin/hledger:
	ghc --make $(MAIN) -o bin/hledger $(BUILDFLAGS)

hledger-web:
	ghc --make hledger-web/hledger-web.hs -o bin/hledger-web -ihledger-web -ihledger $(BUILDFLAGS)

hledger-vty:
	ghc --make hledger-vty/hledger-vty.hs -o bin/hledger-vty -ihledger-vty -ihledger $(BUILDFLAGS)

hledger-chart:
	ghc --make hledger-chart/hledger-chart.hs -o bin/hledger-chart -ihledger-chart -ihledger $(BUILDFLAGS)

hledgernowarnings:
	ghc --make $(MAIN) -o bin/hledger $(BUILDFLAGS) -Werror -v0

# build the profiling-enabled binary. You may need to cabal install
# --reinstall -p some libs.
hledgerp:
	ghc --make $(MAIN) -prof -auto-all -o bin/hledgerp $(BUILDFLAGS)

# build the coverage-enabled binary. coverage-enabled .o files are kept
# separate to avoid contamination.
hledgercov:
	ghc --make $(MAIN) -fhpc -o bin/hledgercov -outputdir .coverageobjs $(BUILDFLAGS)

# build the fastest binary we can
hledgeropt:
	ghc --make $(MAIN) -o bin/hledgeropt $(BUILDFLAGS) -O2 # -fvia-C # -fexcess-precision -optc-O3 -optc-ffast-math

# build a deployable binary for gnu/linux, statically linked
hledgerlinux:
	ghc --make $(MAIN) $(LINUXRELEASEBUILDFLAGS) -o bin/$(BINARYFILENAME)
	-ghc --make hledger-web/hledger-web.hs $(LINUXRELEASEBUILDFLAGS) -o bin/`echo $(BINARYFILENAME) | sed -e 's/hledger/hledger-web/'`
	-ghc --make hledger-vty/hledger-vty.hs $(LINUXRELEASEBUILDFLAGS) -o bin/`echo $(BINARYFILENAME) | sed -e 's/hledger/hledger-vty/'`
	-ghc --make hledger-chart/hledger-chart.hs $(LINUXRELEASEBUILDFLAGS) -o bin/`echo $(BINARYFILENAME) | sed -e 's/hledger/hledger-chart/'`
	@echo 'Please check the binaries look portable, then make compressbinaries:'
	-file bin/*`arch`

# build a deployable binary for mac, using only standard osx libs
hledgermac:
	ghc --make $(MAIN) $(MACRELEASEBUILDFLAGS) -o bin/$(BINARYFILENAME)
	-ghc --make hledger-web/hledger-web.hs $(MACRELEASEBUILDFLAGS) -o bin/`echo $(BINARYFILENAME) | sed -e 's/hledger/hledger-web/'`
	-ghc --make hledger-vty/hledger-vty.hs $(MACRELEASEBUILDFLAGS) -o bin/`echo $(BINARYFILENAME) | sed -e 's/hledger/hledger-vty/'`
	-ghc --make hledger-chart/hledger-chart.hs $(MACRELEASEBUILDFLAGS) -o bin/`echo $(BINARYFILENAME) | sed -e 's/hledger/hledger-chart/'`
	@echo 'Please check the binaries look portable, then make compressbinaries:'
	otool -L bin/*`arch`

# build deployable binaries for windows, assuming cygwin tools are present
hledgerwin: install
	cp ~/.cabal/bin/hledger.exe bin/`echo $(BINARYFILENAME) | dos2unix`
	-cp ~/.cabal/bin/hledger-web.exe bin/`echo $(BINARYFILENAME) | sed -e 's/hledger/hledger-web/' | dos2unix`
	-cp ~/.cabal/bin/hledger-vty.exe bin/`echo $(BINARYFILENAME) | sed -e 's/hledger/hledger-vty/' | dos2unix`
	-cp ~/.cabal/bin/hledger-chart.exe bin/`echo $(BINARYFILENAME) | sed -e 's/hledger/hledger-chart/' | dos2unix`
	@echo 'Please check the binaries look portable, then zip them:'
	ls -l bin/*`arch`

compressbinaries:
	gzip bin/*`arch`

######################################################################
# TESTING

test: codetest

# quick code tests - run all the time
codetest: unittest functest

# moderate pre-commit tests - run before record or before send/push, your choice
committest: hlinttest unittest doctest functest haddocktest warningstest quickcabaltest

# thorough pre-release tests - run before release
# consider hiding dev-build symlinks in Hledger/ first
releasetest: Clean unittest doctest functest warningstest fullcabaltest haddocktest

hlinttest hlint:
	hlint --hint=hlint --report=hlint.html $(SOURCEFILES)

# run unit tests
unittest: unittest-builtin

unittest-builtin: hledger
	@(bin/hledger test \
		&& echo $@ PASSED) || echo $@ FAILED

# XXX doesn't rebuild on hledger source changes
unittest-standalone: tools/unittest
	@(tools/unittest \
		&& echo $@ PASSED) || echo $@ FAILED

# run unit tests without waiting for compilation
unittesths:
	@(runghc $(MAIN) test \
		&& echo $@ PASSED) || echo $@ FAILED

# run functional tests, requires shelltestrunner >= 0.9 from hackage
# 16 threads sometimes gives "commitAndReleaseBuffer: resource vanished (Broken pipe)" here but seems harmless
functest: hledger
	(shelltest tests --implicit=none --plain --threads=16 \
		&& echo $@ PASSED) || echo $@ FAILED

# run doc tests
DOCTESTFILES=\
	hledger/Hledger/Cli/Tests.hs
doctest: tools/doctest
	@for f in $(DOCTESTFILES); do \
		(tools/doctest $$f && echo $@ PASSED) || echo $@ FAILED ; done

# make sure we have no haddock errors
haddocktest:
	@(make --quiet codehaddock \
		&& echo $@ PASSED) || echo $@ FAILED

# make sure the normal build has no warnings
warningstest:
	@(make -s clean \
		&& make --no-print-directory -s hledgernowarnings \
		&& echo $@ PASSED) || echo $@ FAILED

# make sure cabal is reasonably happy
quickcabaltest:
	(cd hledger-lib \
	&& cabal clean \
	&& cabal check \
	&& cabal configure \
	&& cd .. \
	&& cabal clean \
	&& cabal check \
	&& cabal configure \
	&& echo $@ PASSED) || echo $@ FAILED

# make sure cabal is happy in all possible ways
fullcabaltest:
	(cd hledger-lib \
	&& cabal clean \
	&& cabal check \
	&& cabal install \
	&& cabal sdist \
	&& cabal upload dist/hledger-lib-$(VERSION).tar.gz --check -v3 \
	&& cd .. \
	&& cabal clean \
	&& cabal check \
	&& cabal configure \
	&& cabal build \
	&& dist/build/hledger/hledger test 2>&1 | tail -1 | grep -q 'Errors: 0  Failures: 0' \
	&& cabal sdist \
	&& cabal upload dist/hledger-$(VERSION).tar.gz --check -v3 \
	&& echo $@ PASSED \
	) || echo $@ FAILED

# run simple performance benchmarks without saving results
# Requires some commands defined in bench.tests and some BENCHEXES defined above.
quickbench: samplejournals bench.tests tools/simplebench
	tools/simplebench -fbench.tests $(BENCHEXES)
	@rm -f benchresults.*

# run simple performance benchmarks and archive results
# Requires some commands defined in bench.tests and some BENCHEXES defined above.
simplebench: samplejournals bench.tests tools/simplebench
	tools/simplebench -fbench.tests $(BENCHEXES) | tee profs/$(TIME).bench
	@rm -f benchresults.*
	@(cd profs; rm -f latest.bench; ln -s $(TIME).bench latest.bench)

# run criterion benchmark tests and save graphical results
criterionbench: samplejournals tools/criterionbench
	tools/criterionbench -t png -k png

# run progression benchmark tests and save graphical results
progressionbench: samplejournals tools/progressionbench
	tools/progressionbench -- -t png -k png

# generate and archive an execution profile
prof: samplejournals hledgerp
	@echo "Profiling: $(PROFCMD)"
	-$(PROFCMD) +RTS -p -RTS
	mv hledgerp.prof profs/$(TIME).prof
	(cd profs; rm -f latest*.prof; ln -s $(TIME).prof latest.prof)

# generate, archive, simplify and display an execution profile
viewprof: prof
	tools/simplifyprof.hs profs/latest.prof

# generate and display an execution profile, don't save or simplify
quickprof: samplejournals hledgerp
	@echo "Profiling: $(PROFCMD)"
	-$(PROFCMD) +RTS -p -RTS
	echo; cat hledgerp.prof

# generate and archive a graphical heap profile
heap: samplejournals hledgerp
	@echo "Profiling heap with: $(PROFCMD)"
	$(PROFCMD) +RTS -hc -RTS
	mv hledgerp.hp profs/$(TIME).hp
	(cd profs; rm -f latest.hp; ln -s $(TIME).hp latest.hp; \
		hp2ps $(TIME).hp; rm -f latest.ps; ln -s $(TIME).ps latest.ps; rm -f *.aux)

viewheap: heap
	$(VIEWPS) profs/latest.ps

# generate and display a graphical heap profile, don't save
quickheap: samplejournals hledgerp
	@echo "Profiling heap with: $(PROFCMD)"
	$(PROFCMD) +RTS -hc -RTS
	hp2ps hledgerp.hp
	$(VIEWPS) hledger.ps

# generate a code coverage report
coverage: samplejournals hledgercov
	@echo "Generating coverage report with $(COVCMD)"
	tools/coverage "markup --destdir=profs/coverage" test
	cd profs/coverage; rm -f index.html; ln -s hpc_index.html index.html

viewcoverage: coverage
	$(VIEWHTML) profs/coverage/index.html

# get a debug prompt
ghci:
	ghci $(INCLUDEPATHS) $(MAIN)

# generate standard sample journals
samplejournals: data/sample.journal data/100x100x10.journal data/1000x1000x10.journal data/10000x1000x10.journal data/100000x1000x10.journal

data/sample.journal:
	true # XXX should probably regenerate this

data/100x100x10.journal: tools/generatejournal
	tools/generatejournal 100 100 10 >$@

data/1000x1000x10.journal: tools/generatejournal
	tools/generatejournal 1000 1000 10 >$@

data/10000x1000x10.journal: tools/generatejournal
	tools/generatejournal 10000 1000 10 >$@

data/100000x1000x10.journal: tools/generatejournal
	tools/generatejournal 100000 1000 10 >$@

######################################################################
# DOCUMENTATION

# Documentation source files are UPPERCASE files in the top directory.
# site/ contains both html generated from these (UPPERCASE.html) and
# revision-controlled resource files (everything else).  site/api-doc
# contains only generated files.

cleandocs:
	rm -rf site/[A-Z]*.html site/api-doc/*

# rebuild all docs
docs: site codedocs

# build the hledger.org website
# Requires hakyll (cabal install hakyll)
.PHONY: site
site: site/hakyll site/_site/index.html site/_site/profs
	cd site; ./hakyll build

site/_site/index.html:
	mkdir -p site/_site
	cd site/_site; ln -sf README.html index.html; ln -sf ../../profs

site/_site/profs:
	mkdir -p site/_site
	cd site/_site; ln -sf ../../profs

cleansite: site/hakyll
	cd site; ./hakyll clean

previewsite: site/hakyll
	cd site; ./hakyll preview

site/hakyll: site/hakyll.hs
	cd site; ghc --make hakyll.hs $(PREFERMACUSRLIBFLAGS)

siteci:
	cd site; sp --no-exts --no-default-map -o hakyll ghc --make hakyll.hs $(PREFERMACUSRLIBFLAGS) --run preview

viewsite: site
	$(VIEWHTML) site/_site/index.html

# called on each darcs commit
commithook: site

# generate html versions of docs (and the hledger.org website)
# work around pandoc not handling full rst image directive
# html:
# 	for d in $(DOCFILES); do $(PANDOC) --toc -s -H site/header.html -A site/footer.html -r rst $$d >site/$$d.html; done
# 	cd site && ln -sf ../SCREENSHOTS && $(RST2HTML) SCREENSHOTS >SCREENSHOTS.html && rm -f SCREENSHOTS
# 	cd site; rm -f index.html; ln -s README.html index.html; rm -f profs; ln -s ../profs


pdf: docspdf codepdf

# generate pdf versions of main docs
# docspdf:
# 	-for d in $(DOCFILES); do (cd site && ln -sf ../$$d && pandoc $$d -w pdf && rm -f $$d); done

# format all code as a pdf for offline reading
ENSCRIPT=enscript -q --header='$$n|$$D{%+}|Page $$% of $$=' --line-numbers --font=Courier6 --color -o-
codepdf:
	$(ENSCRIPT) --pretty-print=makefile hledger.cabal >cabal.ps
	$(ENSCRIPT) --pretty-print=makefile Makefile >make.ps
	$(ENSCRIPT) --pretty-print=haskell $(SOURCEFILES) >haskell.ps
	cat cabal.ps make.ps haskell.ps | ps2pdf - >code.pdf

# view all docs and code as pdf
PDFS=site/{README,README2,MANUAL,NEWS,CONTRIBUTORS,SCREENSHOTS}.pdf code.pdf
viewall: pdf
	$(VIEWPDF) $(PDFS)

# print all docs and code for offline reading
printall: pdf
	$(PRINT) $(PDFS)

# push latest docs etc. and update the hledger.org site
pushdocs: push
	ssh simon@joyful.com 'make -C/repos/hledger docs'

# generate api & other code docs
codedocs: hscolour apihaddock codehaddock coverage #sourcegraph #hoogle

# browse the code docs
viewcodedocs:
	$(VIEWHTML) site/code-doc/index.html

#http://www.haskell.org/haddock/doc/html/invoking.html
#$(subst -D,--optghc=-D,$(DEFINEFLAGS))
HADDOCK=haddock --optghc='-hide-package monads-tf' --no-warnings --prologue .haddockprologue

.haddocksynopsis: hledger/hledger.cabal
	grep synopsis $< | sed -e 's/synopsis: *//' >$@

.haddockprologue: hledger/hledger.cabal
	cat $< | perl -ne 'print if (/^description:/../^$$/)' | sed -e 's/^description: *//' >$@
	printf "\nThis haddock covers all hledger-* packages, for individual package haddocks see hackage.\n" >>$@

# generate external api docs for the whole project
apihaddock: linkhledgerwebdir .haddockprologue
	$(HADDOCK) --title "hledger API docs (all packages)" \
	 -o site/api-doc \
	 --html \
	 --source-module=../code-doc/src/%{MODULE/./-}.html \
	 --source-entity=../code-doc/src/%{MODULE/./-}.html#%N \
	 $(SOURCEFILESFORHADDOCK)

# generate internal code docs for the whole project
codehaddock: linkhledgerwebdir .haddockprologue
	$(HADDOCK) --title "hledger internal code docs (all packages)" \
	 -o site/code-doc \
	 --ignore-all-exports \
	 --html \
	 --source-module=../code-doc/src/%{MODULE/./-}.html \
	 --source-entity=../code-doc/src/%{MODULE/./-}.html#%N \
	 $(SOURCEFILESFORHADDOCK)

#http://www.cs.york.ac.uk/fp/darcs/hscolour/
HSCOLOUR=HsColour -icss
hscolour:
	mkdir -p site/code-doc/src
	for f in $(SOURCEFILESFORHADDOCK); do \
		$(HSCOLOUR) -anchor $$f -osite/code-doc/src/`echo $$f | sed -e's%[^/]*/%%' | sed -e's%/%-%g' | sed -e's%\.hs$$%.html%'` ; \
	done

sourcegraph:
	for p in $(PACKAGES); do (cd $$p; SourceGraph $$p.cabal); done

# # generate external api docs for each package
# allhaddock: allcabalhaddock\ --hyperlink-source\ --executables

# # generate internal code docs for each package
# allhaddockinternal: allcabalhaddock\ --hyperlink-source\ --executables\ --internal

# # generate hoogle indices for each package
# allhoogle: allcabalhaddock\ --hoogle\ --executables

#set up the hoogle web interface
## We munge haddock and hoogle into a rough but useful framed layout.
## For this to work the hoogle cgi must be built with base target "main".
## XXX move the framed index building into haddock: ?
# 	sed -i -e 's%^></HEAD%><base target="main"></HEAD%' site/api-doc/modules-index.html ; \
# 	cp site/api-doc-frames.html site/api-doc/index.html ; \
# # 	cp site/hoogle-small.html site/api-doc
#
#uses a hoogle source tree configured with --datadir=., patched to fix haddock urls/target frame
# HOOGLESRC=/usr/local/src/hoogle
# HOOGLE=$(HOOGLESRC)/dist/build/hoogle/hoogle
# HOOGLEVER=`$(HOOGLE) --version |tail -n 1 | sed -e 's/Version /hoogle-/'`
# hoogle: hoogleindex
# 	if test -f $(HOOGLE) ; then \
# 		cd site/api-doc && \
# 		rm -f $(HOOGLEVER) && \
# 		ln -s . $(HOOGLEVER) && \
# 		cp -r $(HOOGLESRC)/src/res/ . && \
# 		cp -p $(HOOGLE) index.cgi && \
# 		touch log.txt && chmod 666 log.txt ; \
# 	else \
# 		echo "Could not find $(HOOGLE) in the hoogle source tree" ; \
# 	fi
#
#generate a hoogle index
# hoogleindex:
# 	$(HADDOCK) -o site/api-doc --hoogle $(MAIN) && \
# 	cd site/api-doc && \
# 	hoogle --convert=main.txt --output=default.hoo

######################################################################
# RELEASING

# Version numbering. See also VERSION and Version.hs.
#
# hledger's version number appears in:
#  hledger --version
#  hledger's cabal file
#  darcs tags
#  hackage tarball filenames
#  hackage pages
#
# Some old version numbering goals:
# 1 automation, robustness, simplicity, platform independence
# 2 cabal versions must be all-numeric
# 3 release versions can be concise (without extra .0's)
# 4 releases should have a corresponding darcs tag
# 5 development builds should have a precise version appearing in --version
# 6 development builds should generate cabal packages with non-confusing versions
# 7 there should be a way to mark builds/releases as alpha or beta
# 8 it should be easy to darcs get the .0 release even after bugfix releases
# 9 avoid unnecessary compiling and linking
# 10 minimise rcs noise and syncing issues (commits, unrecorded changes)
#
# Current policy:
#
# - We follow http://haskell.org/haskellwiki/Package_versioning_policy
#
# - The full release version is ma.jor.minor, where minor is 0 for a
#   normal release or 1..n for bugfix releases.
#
# - The elided release version is ma.jor when minor is 0. We use it for
#   hackage releases when possible, trusting it doesn't cause trouble..
#
# - The build version is ma.jor.minor+patches, where patches is the number
#   of patches applied in the current repo since the last release tag.
#
# - The release tag in the repo is the full release version.
#
# - hledger --version shows the release version or build version as
#   appropriate.
#
# - The VERSION file must be updated manually before a release.
#
# - "make simplebench" depends on version numbers in BENCHEXES, these also
#   must be updated manually.
#
# - "make" updates the version in most other places, and defines PATCHES.
#   Note "cabal build" should also do this but doesn't yet.
#
# - "make release" additionally records the main version number-affected
#   files, and tags the repo with the release tag.

# Build a release, tag the repo, prepare a cabal package
# First update VERSION. Eg:
# a normal release: echo 0.7   >VERSION; make release
# a bugfix release: echo 0.7.1 >VERSION; make release
release: releasetest setandrecordversion tagrelease

# Upload the latest cabal package and update hledger.org
upload: sdist hackageupload pushdocs

releaseandupload: release upload


# update the version number in local files, and prompt to record changes
# in these files. Triggered by "make release".
setandrecordversion:
	darcs record -m "bump version" $(VERSIONFILE) $(VERSIONSENSITIVEFILES)

# update the version string in local files. This should be run immediately
# after editing the VERSION file.
setversion: $(VERSIONSENSITIVEFILES)

# re-update version string even if it seems unchanged
Setversion:
	touch $(VERSIONFILE); make setversion

hledger/Hledger/Cli/Version.hs: $(VERSIONFILE)
	perl -p -e "s/(^version *= *)\".*?\"/\1\"$(VERSION3)\"/" -i $@

hledger-lib/hledger-lib.cabal: $(VERSIONFILE)
	perl -p -e "s/(^ *version:) *.*/\1 $(VERSION)/" -i $@

hledger/hledger.cabal: $(VERSIONFILE)
	perl -p -e "s/(^ *version:) *.*/\1 $(VERSION)/" -i $@
	perl -p -e "s/(^[ ,]*hledger-lib *[>=]=) *.*/\1 $(VERSION)/" -i $@

hledger-chart/hledger-chart.cabal: $(VERSIONFILE)
	perl -p -e "s/(^ *version:) *.*/\1 $(VERSION)/" -i $@
	perl -p -e "s/(^[ ,]*hledger *[>=]=) *.*/\1 $(VERSION)/" -i $@
	perl -p -e "s/(^[ ,]*hledger-lib *[>=]=) *.*/\1 $(VERSION)/" -i $@

hledger-vty/hledger-vty.cabal: $(VERSIONFILE)
	perl -p -e "s/(^ *version:) *.*/\1 $(VERSION)/" -i $@
	perl -p -e "s/(^[ ,]*hledger *[>=]=) *.*/\1 $(VERSION)/" -i $@
	perl -p -e "s/(^[ ,]*hledger-lib *[>=]=) *.*/\1 $(VERSION)/" -i $@

hledger-web/hledger-web.cabal: $(VERSIONFILE)
	perl -p -e "s/(^ *version:) *.*/\1 $(VERSION)/" -i $@
	perl -p -e "s/(^[ ,]*hledger *[>=]=) *.*/\1 $(VERSION)/" -i $@
	perl -p -e "s/(^[ ,]*hledger-lib *[>=]=) *.*/\1 $(VERSION)/" -i $@

hledger-web/.hledger/web/.version: $(VERSIONFILE)
	cat $(VERSIONFILE) >$@

MANUAL.markdown: $(VERSIONFILE)
	perl -p -e "s/(^This is the.*?manual for hledger.*?) +[0-9.]+/\1 $(VERSION3)./" -i $@

DOWNLOAD.markdown: $(VERSIONFILE)
	perl -p -e "s/hledger-[0-9.]+-/hledger-$(VERSION)-/g" -i $@

tagrelease:
	darcs tag $(VERSION3)

sdist:
	cd hledger-lib; cabal sdist
	cabal sdist

# display a hackage upload command reminder
hackageupload:
	cabal upload hledger-lib/dist/hledger-lib-$(VERSION).tar.gz -v3
	cabal upload dist/hledger-$(VERSION).tar.gz -v3

# send unpushed patches to the mail list
send:
	darcs send http://joyful.com/repos/hledger --to=hledger@googlegroups.com --edit-description  

# push patches and anything else pending to the public server
push: pushprofs pushbinary
	darcs push simon@joyful.com:/repos/hledger

# pull anything pending from the public server
pull: pullprofs
	darcs pull -a simon@joyful.com:/repos/hledger

# push any new profiles and benchmark results to the public site
# beware, results will vary depending on which machine generated them
pushprofs:
	rsync -azP profs/ simon@joyful.com:/repos/hledger/profs/

# fetch any new profiles and benchmark results from the public site
pullprofs:
	rsync -azP simon@joyful.com:/repos/hledger/profs/ profs/

# compress the just-built platform binary. make hledgerPLATFORM first. Use
# the win variant on windows.
compressbinary:
	gzip -9 bin/$(BINARYFILENAME)
compressbinarywin:
	cd bin; zip -9 $(BINARYFILENAME).zip $(BINARYFILENAME)

# push the last-updated platform binary to the public download directory
pushbinary:
	cd bin; rsync -aP `ls -t | head -1` simon@joyful.com:/repos/hledger/site/download/


# show project stats useful for release notes
stats: showlastreleasedate showreleaseauthors showloc showcov showlocalchanges showreleasechanges #simplebench #showerrors

showreleaseauthors:
	@echo Patch authors since last release:
	@darcs changes --from-tag . |grep '^\w' |cut -c 31- |sort |uniq
	@echo

showloc:
	@echo Lines of code including tests:
	@sloccount `ls $(SOURCEFILES)` | grep haskell:
	@echo

showcov: hledgercov
	@echo Test coverage:
	@tools/coverage report test

showlastreleasedate:
	@echo Last release date:
	@darcs changes --from-tag . | tail -2
	@echo

# showerrors:
# 	@echo Known errors:
# 	@awk '/^** errors/, /^** / && !/^** errors/' NOTES | grep '^\*\*\* ' | tail +1
# 	@echo

showlocalchanges:
	@echo Local changes:
	@-darcs push simon@joyful.com:/repos/hledger --dry-run | grep '*' | tac
	@echo

showcodechanges:
	@echo Code changes:
	@darcs changes --matches "not (name docs: or name site: or name tools:)" | egrep '^ +(\*|tagged)'
	@echo

showunreleasedchanges:
	@echo "Feature/bugfix changes since last release: ("`darcs changes --from-tag . --count`")"
	@darcs changes --from-tag . --matches "not (name docs: or name doc: or name site: or name tools:)" | grep '*'
	@echo

######################################################################
# MISCELLANEOUS

# fix permissions (eg after darcs get)
fixperms:
	chmod +x tools/* $(MAIN) hledger-*/Main.hs

tag: emacstags

emacstags:
	-@rm -f TAGS; hasktags -e $(SOURCEFILES) $(CABALFILES) Makefile

clean:
	rm -rf `find . -name "*.o" -o -name "*.hi" -o -name "*~" -o -name "darcs-amend-record*" -o -name "*-darcs-backup*"`

Clean: clean cleandocs
	rm -f bin/hledger TAGS tags

