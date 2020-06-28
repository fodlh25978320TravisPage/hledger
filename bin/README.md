Miscellaneous hledger add-ons, bash scripts, example make rules, etc. 

The hledger-*.hs scripts here are example/experimental hledger [add-on commands], including:

- hledger-check.hs      - check more complex account balance assertions
- hledger-smooth.hs     - an attempt at automatically splitting infrequent/irregular transactions
- hledger-swap-dates.hs - print transactions with their date and date2 fields swapped
- hledger-combine-balances.hs  - render two balance reports as single multi-column one
- hledger-balance-as-budget.hs - use one balance report as the budget for the other one

Note these are not tested as much as the rest of hledger, and some of them may be only proof of concepts.

They are easiest to run reliably if you have [stack] in your $PATH;
they will install required dependencies and compile themselves as needed.
(You can also run them with cabal or runghc, or compile them with ghc, if you take care of the dependencies.)

[add-on commands]: http://hledger.org/hledger.html#add-on-commands
[stack]: https://www.fpcomplete.com/haskell/get-started

## Installing a single script

    $ curl -sO https://raw.githubusercontent.com/simonmichael/hledger/master/bin/hledger-check.hs
    $ chmod +x hledger-check.hs
    $ ./hledger-check.hs --help

If you put the script somewhere in your $PATH, it will also show up as a hledger command,
so this also works:

    $ hledger check -- --help

Note the `--`, which is required to separate script options from hledger options:

    $ hledger [HLEDGEROPTS] ADDONCMD [-- ADDONOPTS]

## Installing all scripts

    $ git clone https://github.com/simonmichael/hledger
    $ # add hledger/bin/ to your $PATH
    $ hledger  # addons appear in command list

