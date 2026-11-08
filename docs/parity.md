# Parity with the bash script

`devsweep` started as a Swift port of `devclean`, a bash script in
[a dotfiles repository](https://github.com/JaviLorbada/dotfiles). That is
the only thing the name devclean means here: the original script, its bats
suite and the parity checks. Run under the script's name, the tool prints
exactly what the script prints, byte for byte, which is how those checks
run it.

## How it's tested

Three layers, all in CI. [development.md](development.md) has the commands.

1. **Swift Testing**: the kit and the app, each test on a fake home folder
   in its own temp folder, with fake tools, Trash and clock.
2. **The script's own bats suite**, copied unchanged from the dotfiles
   repository and run against the Swift binary: 52 of 52 pass. This is the
   acceptance test.
3. **Side by side**: the bash script and the binary run against the same
   fake home with the same stubs on `PATH`, and their output, exit status,
   tool calls and the folders left after `--run` are compared. They are
   identical.

## How the tool matches the script

The flags, environment variables, messages, exit codes and output are the
script's. Arguments are read with the script's own rules first (left to
right, the first unknown option fails, `--help` wins only if nothing before
it failed, `--skip` and `--projects` take the next argument whatever it is),
then handed to swift-argument-parser, which keeps the script's exact errors.

The whole run, from preflight to "Done.", is `CommandLineSession` in the
kit, writing to a `Terminal`; the binary gives it standard input and output
and the tests a buffer, so the tests exercise the code the binary runs.
Every tool is found through `PATH` when it runs, and runs with `LC_ALL=C`.

Sizes count allocated blocks the way `du -sk` does: every entry's
`st_blocks`, hard-linked files once, symlinks never followed. That is why
an installed Xcode shows about 3.7 GB, not the 9 GB Finder reports: its
files are stored compressed, and 3.7 GB is what removing it frees.

## Where it's stricter than the script

- Device Support folder names containing a tab or newline broke the
  script's rows; they are kept and never listed.
- A DerivedData project name longer than 21 bytes is cut at a whole
  character, never in the middle of one.
- A runtime whose last-used date doesn't parse made the script abort; it is
  now simply not flagged.
- With `HOME` unset the script failed with "HOME: unbound variable"; the
  port says "HOME must be your home folder."
- A folder whose contents can't be read is reported with what could be
  measured, as the script did, and flagged as unknown so the app doesn't
  show zero.
