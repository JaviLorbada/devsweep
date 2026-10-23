# Development

## Requirements

macOS 26 and Xcode 26 or newer (Swift 6.2). For the acceptance suite, also
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
```

The variables (`DEVSWEEP_CAPTURE`, `DEVSWEEP_SCREEN`, `DEVSWEEP_SELECT`,
`DEVSWEEP_PRESS`, `DEVSWEEP_SETTINGS`, `DEVSWEEP_MENU`, `DEVSWEEP_PROBE` and
others) are documented at the top of `Sources/DevSweepApp/DebugLaunch.swift`.
`DEVSWEEP_PROBE` writes whether every column fits the window, read from the
view hierarchy, which is how the window was checked at 900, 1100, 1280 and
1400 points wide.

## Commits

Imperative subject, a short body saying why, one coherent change per commit
with tests passing. See `AGENTS.md` for the rest of the rules.
