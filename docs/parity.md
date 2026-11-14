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
   repository and run against the Swift binary: 57 of 57 pass. This is the
   acceptance test.
3. **Side by side**: the bash script and the binary run against the same
   fake home with the same stubs on `PATH`, for the report, `--help`,
   `--version` and `--run`, and their output, exit status, tool calls and
   the folders left after `--run` are compared. They are identical.

## How the tool matches the script

The flags, environment variables, messages, exit codes and output are the
script's. Arguments are read with the script's own rules first (left to
right, the first unknown option fails, `--help` wins only if nothing before
it failed, `--skip` and `--projects` take the next argument whatever it is),
then handed to swift-argument-parser, which keeps the script's exact errors.
As `devsweep` the tool also takes `--version`, and its help lists it; the
script has none, so under its name `--version` is an unknown option and the
help is the script's.

The same goes for the items the script doesn't have: `cocoapods-pods`,
`cargo-builds` and `node-modules`. As `devsweep` the tool lists them, and
its help and `--skip` name them. Under the script's name it skips them
(`Item.known(by:)`), `--skip` rejects them with the script's error and its
list of items, and the help leaves them out, so no search for them runs and
the report is the script's.

As `devsweep`, every search for build folders also keeps out of every other
build folder (`.build`, `build`, `target`, `.venv`, `node_modules`, `Pods`),
so a folder inside another counts once, as part of the outer one: a
`node_modules` in Gradle's `build` folder, or a `.build` in Cargo's
`target`. Under the script's name the searches are the script's `find`,
which looks inside them (`ScanConfig.outermostBuildFolders`).

The whole run, from preflight to "Done.", is `CommandLineSession` in the
kit, writing to a `Terminal`; the binary gives it standard input and output
and the tests a buffer, so the tests exercise the code the binary runs.
Every tool is found through `PATH` when it runs, and runs with `LC_ALL=C`.

Sizes count allocated blocks the way `du -sk` does: every entry's
`st_blocks`, hard-linked files once, symlinks never followed. That is why
an installed Xcode shows about 4.0 GB, not the 9 GB Finder reports: its
files are stored compressed, and 4.0 GB is what removing it frees.

Sizes print as Finder writes them, in thousands and rounded (`SizeText`, the
app's too), and Homebrew's sizes are read in thousands, as Homebrew counts
them. Free space is Finder's figure, with what macOS frees on its own, and
`df`'s when that can't be read. The script reads Finder's figure through
`osascript`, so under its name the tool does the same, through `PATH`, and
the bats suite can stub it; as `devsweep` and in the app it asks macOS
directly.

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
- Playwright MCP kept each logged-in browser profile in an `mcp-*` folder
  inside `~/Library/Caches/ms-playwright`, which the script removes whole.
  When one is there, the port removes only the other folders, the browsers,
  and the profiles stay.
