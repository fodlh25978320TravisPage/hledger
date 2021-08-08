help\
Show the hledger user manual in one of several formats,
optionally positioned at a given TOPIC (if possible).

TOPIC is any heading in the manual,
or the start of any heading (but not the middle).
It is case insensitive.

Some examples: 
`commands`, `print`, `forecast`, `"auto postings"`, `"commodity column"`.

_FLAGS

This command shows the user manual built in to this hledger version.
It can be useful if the correct version of the hledger manual,
or the usual viewing tools, are not installed on your system.

By default it uses the best viewer it can find in $PATH, in this order:
`info`, `man`, $PAGER (unless a topic is specified), `less`, or stdout.
When run non-interactively, it always uses stdout.
Or you can select a particular viewer with the 
`-i` (info), `-m` (man), or `-p` (pager) flags.
