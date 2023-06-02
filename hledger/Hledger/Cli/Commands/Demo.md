## demo

Play demos of hledger usage in the terminal, if asciinema is installed.

_FLAGS

Run this command with no argument to list the demos.
To play a demo, write its number or a prefix or substring of its title.
Tips:

Make your terminal window large enough to see the demo clearly.

Use the -s/--speed SPEED option to set your preferred playback speed,
eg `-s4` to play at 4x original speed or `-s.5` to play at half speed.
The default speed is 2x.

Other asciinema options can be added following a double dash,
eg `-- -i.1` to limit pauses or `-- -h` to list asciinema's other options.

During playback, several keys are available:
SPACE to pause/unpause, . to step forward (while paused),
CTRL-c  quit.

Examples:
```shell
$ hledger demo               # list available demos
$ hledger demo 1             # play the first demo at default speed (2x)
$ hledger demo install -s4   # play the "install" demo at 4x speed
```
