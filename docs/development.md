# Development

## Requirements

macOS 26 and Xcode 27 or newer (Swift 6.4). For the acceptance suite, also
[bats-core](https://github.com/bats-core/bats-core) and a checkout of the
[dotfiles repository](https://github.com/JaviLorbada/dotfiles) that holds
the original bash script and its tests. For lint, SwiftFormat and SwiftLint:

```bash
brew install bats-core swiftformat swiftlint
```

## The three test layers

1. **Swift Testing** (`make test`): unit and integration tests for the kit and
   the app, in parallel. Each test builds a fake home in its own temp folder
   and fakes the tools, the Trash and the clock through `Dependencies`, so no
   test touches your home folder or runs simctl or brew.
2. **The bats suite** (`Scripts/bats.sh <dotfiles>`): the bash script's own
   tests, copied unchanged from the dotfiles repository, run against the Swift
   binary. This is the acceptance test. It must pass in full; if it fails,
   the Swift tool no longer behaves like the script.
3. **Side by side** (`RUN=1 Scripts/compare.sh <dotfiles>`): the bash script and
   the binary against the same fake home with the same stubs on `PATH`,
   comparing what they print, their exit status, the tools they call and the
   folders left after `--run`.

`make acceptance DOTFILES=<dotfiles>` runs layers 2 and 3. CI runs all three
against the dotfiles commit pinned in `.github/workflows/ci.yml`.

CI also builds with warnings as errors, in debug and in release, and
CodeQL scans the Swift code on each push and weekly. Every Action is
pinned to a commit, with its release in a comment.

## When CI fails

A failing test shows where you look first, not deep in a log:

- **On its line.** An annotation in the pull request's Files tab, titled with
  the suite and the test: what was expected, and what came instead.
- **On the run's summary page.** A table of every failure, each linked to its
  line, in short lines: what was expected, and what came instead. When
  both sides are text of several lines, such as the report, what came
  instead is the first line that differs. A green run says how many tests
  passed; a run that crashes says so, with the crash's message.

The tests run with `--quiet`, so their log is the failures and the totals.
`Scripts/test_report.sh` writes the annotations and the table from Swift
Testing's event stream, and folds every value Swift Testing listed into the
report step's log, a group per failure. It needs only jq, which macOS has. It
reads version 6.4 of the event stream and fails, saying so, on any other: a
new Xcode in CI that changes the format means changing `ci.yml` and the script
together. To read a run the same way on your Mac:

```sh
swift test --parallel --quiet --event-stream-output-path /tmp/tests.jsonl --event-stream-version 6.4
Scripts/test_report.sh /tmp/tests.jsonl
```

The bats suite and the comparison print little enough to read as they are.
The comparison runs even when the bats suite fails, so both say what differs.

## Lint and format

`make format` rewrites `Sources` and `Tests` with `.swiftformat`; `make lint`
checks both tools' rules and fails on any warning. Format your changes before
committing; CI runs lint on every push.

## Looking at the window without clicking

Debug builds read a few environment variables, so the window can be checked
from a script on a fake home, without screen recording permission:

```bash
WIDTH=1280 Scripts/snapshot.sh build/snapshots overview runtimes-light
SELECT=swiftpm-builds PRESS="and 2 more" WIDTH=1280 Scripts/snapshot.sh build/snapshots overview
SETTINGS=Folders WIDTH=1280 Scripts/snapshot.sh build/snapshots settings
MENU=1 WIDTH=1280 Scripts/snapshot.sh build/snapshots menu
MENU=Help WIDTH=1280 Scripts/snapshot.sh build/snapshots help-menu-light
CHART=blocks WIDTH=1280 Scripts/snapshot.sh build/snapshots overview
SCROLL=200 HEIGHT=700 WIDTH=1280 Scripts/snapshot.sh build/snapshots overview-light
```

While you work in another app, macOS doesn't let the app activate itself,
and the window would draw its inactive look. So once the scan is done,
`snapshot.sh` activates it through Launch Services, as a Dock click would,
but only once it is listed running, so it never starts a second copy.
With the screen locked nothing can activate it; `ACTIVE=1` draws it as
active then, though AppKit still draws checkboxes and prominent buttons
inactive.

The variables (`DEVSWEEP_CAPTURE`, `DEVSWEEP_SCREEN`, `DEVSWEEP_SELECT`,
`DEVSWEEP_PRESS`, `DEVSWEEP_CHART`, `DEVSWEEP_SCROLL`, `DEVSWEEP_ACTIVE`,
`DEVSWEEP_SETTINGS`, `DEVSWEEP_MENU`, `DEVSWEEP_PROBE` and others) are
documented at the top of `Sources/DevSweepApp/Debug/DebugLaunch.swift`.
`DEVSWEEP_PROBE` writes whether every column fits the window, read from the
view hierarchy, which is how the window was checked at 900, 1100, 1280 and
1400 points wide.

## Opening the latest build

```bash
make app && Scripts/open_app.sh
```

`make app` builds DevSweep Dev: its own icon, its own bundle id,
settings and last scan, so it runs beside the DevSweep you installed and the
two can be told apart. `open` alone brings a DevSweep Dev that is already
running forward, old build and all. `Scripts/open_app.sh` asks it to quit,
waits for it to exit, then opens `build/DevSweep Dev.app` and says which
commit it was built from; the installed DevSweep keeps running. Quitting it
takes the terminal's Automation permission for DevSweep Dev; when macOS
refuses, the script says so and opens nothing. Nor does it open a bundle
built before a change to what goes into it (the sources, the package,
`version.env`, the icon or the packaging script): it says to run
`make app` first, and leaves the running copy alone. A commit that
changes only docs doesn't count.

## Commits

Imperative subject, a short body saying why, one coherent change per commit
with tests passing. See `AGENTS.md` for the rest of the rules.
