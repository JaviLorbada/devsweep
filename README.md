# devclean for Mac

A native macOS 26 app and a Swift command line tool that show how much space
developer caches take and reclaim it. They replace `bin/devclean`, the bash
script in the dotfiles repo, and keep its safety rules word for word.

`HANDOFF.md` holds the decisions, the behavior being ported and the UI spec.

## Status

| Milestone | State |
|---|---|
| M1, engine and CLI parity | Done. The bats suite passes unchanged against the Swift binary. |
| M2, app shell | Done. Window, sidebar, ring, items, inspector, live scan. |
| M3, cleaning in the app | Done. Clean per item or marked, Trash with Put back, delete for good, quit prompt, Blocks. |
| M4, extras screens | Done. Runtimes and Xcode versions, Remove runtime with confirmation, Reveal in Finder. |

## Requirements

macOS 26 and Xcode 26 or later (built and tested with Xcode 27.2, Swift 6.4).
`bats-core` only to run the original acceptance suite (`brew install bats-core`).
The only package dependency is swift-argument-parser.

## Build, test, run

```bash
swift build                       # everything: kit, CLI, app
swift test                        # the swift-testing suite
.build/debug/devclean             # report only; deletes nothing
.build/debug/devclean --help
```

`--run` deletes, after asking. Try it against a fake home first, the way the
tests do; never with `--yes` on a machine you care about until you trust it.

## The app

```bash
scripts/build-app.sh              # builds build/DevClean.app (release, signed ad hoc)
open build/DevClean.app
swift run DevCleanApp             # or run it unbundled while developing
```

The window scans as soon as it opens, in report mode: it reads the home
folder and deletes nothing until you clean something. It reads `HOME` and
the same environment variables as the CLI, so launching the binary with
another `HOME` and `PATH` points it at a fake home and stub tools. An app
opened from Finder gets a short `PATH` without Homebrew, so the app adds
`/opt/homebrew/bin` and `/usr/local/bin` at the end of whatever `PATH` it has.

`scripts/snapshot.sh [folder] [screen...]` builds a debug bundle, makes a
fake home with something in every item and stubs for the tools, and has the
app draw its window into PNG files: `overview`, `scanning`, `blocks`,
`runtimes`, `xcodes`, `remove-runtime`, `cleaned`, `putback`, each also as
`name-light`. `remove-runtime` shows the confirmation sheet and never
confirms it. `cleaned` cleans what starts marked and `putback` then puts the
SwiftPM cache back, so those two exercise the real cleaning code; each
screen gets a fresh fake home, the Trash is pointed at a folder inside it,
and the stubs refuse `simctl delete` and `brew cleanup`. It never touches the
real home folder. Grabbing the real window needs screen recording
permission, so the debug build draws the same content views with
`ImageRenderer` instead; controls that AppKit draws (checkboxes, link
buttons, glass buttons) come out as placeholders in those images, and the
toolbar is approximated.

The real window is checked with a debug-only launch harness
(`DebugLaunch.swift`), used on the real home in report mode. Launched with
the window frame as a defaults argument (`-"NSWindow Frame main" "x y w h
screen"`), `DEVCLEAN_SCREEN` (`overview`, `xcodes`, `runtimes`), optionally
`DEVCLEAN_SKIP`, and `DEVCLEAN_PROBE=/path`, the app opens at that size,
scans, switches screens the way a click in the sidebar does, and writes
whether the content fits: each split view against the window, each column,
whether the inspector shows, and every scroll view whose content is wider
than it. Read from the view hierarchy, so it needs no screen recording. It
also records how long the scan took. Resizing a running window from code is
no test of a person dragging its edge: SwiftUI keeps its own record of the
window's size and puts it back.

Window layout:

- The sidebar is 200 to 300 points wide, the inspector 300, and the center
  at least 460. The window never gets narrower than sidebar plus center
  (670 points), so nothing is clipped.
- The inspector is a column inside the detail area, not SwiftUI's
  `.inspector`, which resizes the window when it shows or hides. It hides
  when the detail area can't hold the center at its minimum next to it (about
  1000 points of window) and comes back with a little room to spare. The
  inspector button in a window too narrow for it widens the window.
- The window has a fixed ideal size. SwiftUI animates a window to its
  content's ideal size whenever an animated change alters that size, and
  with flexible content the window shrank or grew with scan events.
- In a narrow center the ring scales down from 240 to 150 points, the family
  legend drops its share column, the items table drops its bar column
  first, Xcode and runtime rows drop the bar and then the date, and the
  footer shortens its Trash label. These choices are made at layout time
  from the width offered, never kept as state: a view whose minimum follows
  the width it last had makes SwiftUI grow the window without end.
- Inspectors scroll. A column that isn't in a scroll view asks the window
  for the height of its text at its narrowest, which was thousands of points.
- The app ignores saved session state, so it always opens its window.

What is in the window:

- Sidebar: Overview; the five families with their color and size, which
  select the family's biggest item; Xcode versions and Simulator runtimes
  with their sizes; and a meter for the boot volume (used, reclaimable, free).
- Toolbar: title and status line, a capsule with what is being measured
  and a thin progress bar, Ring or Blocks, Scan Again that turns into Stop.
- Ring: Swift Charts `SectorMark` rings, families inside and their items
  outside, two degrees or so apart, the total in the hole. Clicking a
  segment selects it; the others dim. To the right, a stacked family bar
  and the family legend with share and size.
- Items: mark, color, name and family, a proportional bar, size, and the
  row's state (Waiting, a pulsing Measuring, Not measured if the scan was
  stopped). Measured items sort largest first as they arrive.

Scanning:

- The window scans four items at a time, the quick fixed folders first and
  DerivedData last, with up to four folders of one item (DerivedData's
  parts, build folders) measured at once and the Xcodes and runtimes listed
  alongside (`ScanOptions.interactive`). Walks run on GCD threads, not the
  few threads Swift concurrency uses for tasks. The command line keeps
  `ScanOptions.report`, one item at a time in report order, so its output is
  unchanged.
- An item being measured counts up live in the ring, the hero number, the
  sidebar and the table, from the scan's progress events, shown about ten
  times a second.
- The last finished scan is saved to
  `~/Library/Application Support/DevClean/last-scan.json` (inside the home
  folder it describes) and shown, dimmed, on the next launch with "Last
  scanned 3 hours ago", while the new scan replaces it item by item. Nothing
  from the last scan can be cleaned until it has been measured again. After
  cleaning, the saved copy records the cleaned items as empty.
- On this machine the full scan, `device-installs` aside, takes about 25
  seconds in the window. Measured back to back on warm caches, the engine
  scans the same 331.5 GB in 23 seconds this way against 95 seconds one
  item at a time.
- Inspector: family, name, size and state, where it lives with Reveal in
  Finder, what cleaning does, and for DerivedData what is inside: the
  compilation and module caches and each project with its last build, a bar
  and a "project gone" badge. At the bottom: Clean, Put Back, or a disabled
  Measuring.
- Blocks: the live items as a squarified treemap (the layout is
  `Treemap.squarify` in the kit), tinted with each item's color, labeled where
  the cell is big enough, the selected one stronger. Cells slide into place as
  items are measured or cleaned.

Cleaning:

- The three biggest items start marked once the scan ends, unless you
  changed the marks during the scan. Clean on a row or in the inspector
  cleans one item; the footer button cleans everything marked.
- "Move to Trash, so anything can be put back" is on by default and uses
  `FileManager.trashItem`, so Finder's Put Back works too. Put Back in the
  inspector moves the folders back, but only if nothing has taken their place
  and the folder that held them still resolves to the same place in home.
  Turned off, cleaning deletes for good, after a confirmation.
- Simulators and Homebrew are removed by `simctl` and `brew` whatever the
  mode, so they can't be put back; cleaning them always asks first.
- When an Xcode item is about to be cleaned and Xcode or Simulator is open,
  the app asks to quit them ("Quit and Clean"), or to clean only the other
  items, or to cancel. Quitting is the normal request, so Xcode still asks
  about unsaved work; if it doesn't quit within 15 seconds nothing is
  cleaned. The check runs again right before each Xcode item.
- Every path goes through the kit's recheck before it moves. Anything left
  alone is reported in an alert and in the notes under the items.
- Put Back is offered until the next scan. After that the folders are still
  in the Trash, where Finder can put them back.

Xcodes and runtimes (never touched by a scan or a clean):

- Simulator runtimes: one row per runtime with its last use, a bar, its
  size, and a badge when it looks unused (90 days or more, or no
  simulators). The inspector says why it is flagged, what removing it does,
  and the exact command. Remove Runtime opens a sheet that shows that
  command again and runs it only on confirmation, through
  `Engine.removeRuntime`, which refuses ids `simctl` could read as options.
  The installed Xcodes follow, and a note that Archives are never listed.
- Xcode versions: each Xcode with its version and build, the one
  `xcode-select` points at, last opened, size, and Reveal in Finder. devclean
  never removes an Xcode.

The CoreDevice install cache lives in another app's container. The first
time anything run from a given app reads it, macOS asks whether that app may
access data from other apps, and the read waits until someone answers. The
CLI and the app behave the same: the scan pauses on that item until the
prompt is answered, and a refusal shows up as an unknown size, not an error.

Colors: marks use the palette from HANDOFF section 4; chrome uses system
materials and semantic colors, so light and dark both work. Both palettes
are validated: the dark one on the dark card, the light one on a white card.
In light mode three family hues sit below 3:1 against white, which is
acceptable only because every segment also has a labeled legend row and a
table row; those labels stay in both appearances.

## Layout

```
Package.swift                 swift-tools-version 6.2, macOS 26
Sources/DevCleanKit/          the engine, no UI imports
  Model/        Item (the 11 ids), ItemResult, ScanEvent, Extras
  Config/       ScanConfig: home, project and applications folders, skips
  Safety/       PathPolicy (home-only, no symlink, resolve, recheck), GitTracking
  Scanners/     one Scanner per item, the project folder search, extras
  Measure/      SizeMeasurer (du -sk semantics, with progress), DiskSpace (df -k)
  Clean/        Cleaner (trash or delete, recheck first, Put back), TrashService
  Tools/        ProcessRunner and the simctl, brew, defaults, xcode-select,
                git, pgrep and Spotlight clients, as protocols with live versions
  Report/       the text report, byte for byte what bin/devclean prints
  CommandLine/  the script's argument rules and its main flow as a session
Sources/devclean/             the CLI on swift-argument-parser
Sources/DevCleanApp/          the SwiftUI app: model, views, palette, debug snapshots
Tests/DevCleanKitTests/       swift-testing, a fake home per test, fake tools
scripts/bats.sh               runs the original bats suite against the binary
scripts/compare.sh            diffs the bash script and the binary on one fake home
scripts/build-app.sh          wraps the app executable into build/DevClean.app
scripts/snapshot.sh           draws the window for a fake home into PNG files
```

## How the CLI matches the script

The flags, environment variables (`DEVCLEAN_PROJECT_DIRS`,
`DEVCLEAN_APPLICATIONS_DIRS`, `NO_COLOR`), messages, exit codes and output are
the script's. The CLI reads arguments with the script's own rules first
(left to right, first unknown option fails, `--help` wins only if nothing
before it failed, `--skip` and `--projects` take the next argument whatever it
is), then hands what they accept to swift-argument-parser. That keeps the
script's exact errors, which the parser would otherwise word its own way.

The whole run, from preflight to "Done.", is `CommandLineSession` in the kit,
writing to a `Terminal`. The binary gives it standard input and output; the
tests give it a buffer. So the tests exercise the same code the binary runs,
including the confirmation prompt, the refusal while Xcode or Simulator is
running, and the refusal without a terminal or `--yes`.

Every tool is found through `PATH` at the moment it runs, never at a fixed
path, and runs with `LC_ALL=C`. That is what lets the bats suite put its stubs
for `xcrun`, `brew`, `pgrep`, `defaults` and `xcode-select` in front.

Sizes count allocated blocks the way `du -sk` does: every entry's
`st_blocks`, files with several hard links once, symlinks never followed, not
even the top one. HANDOFF suggested `totalFileAllocatedSizeKey`; that key
counts a hard-linked file once per name, so the report would print different
numbers from the script. Free space is `statfs`'s available blocks, the
column `df -k` prints.

## The bats suite

`scripts/bats.sh` runs `test/devclean.bats` from the dotfiles checkout
(default `~/Documents/Workspace/dotfiles`, or pass a path, or set `DOTFILES`)
against the Swift binary without changing a byte of it:

```bash
scripts/bats.sh
```

The suite runs `"${DOTFILES_DIR}/bin/devclean"`, and `test_helper.bash` sets
`DOTFILES_DIR` to the parent of its own folder. So the script builds the
binary, creates a throwaway folder with `bin/devclean` as a symlink to it and
`test/` holding copies of `devclean.bats` and `test_helper.bash`, checks with
`cmp` that the copies are identical to the originals, and runs bats there.
The dotfiles checkout is only read.

Result: 52 of 52 pass. (HANDOFF says 50; the file has 52.)

## Side by side with the script

`scripts/compare.sh` builds one fake home with something for every item
(DerivedData with seven projects, one gone and one with a long name; an
unavailable simulator; Device Support with arm64e copies and unparseable
names; a 1.4 GB SwiftPM cache; build folders, including one in a repository
with a corrupt index and one tracked in git; two Xcodes; four runtimes), runs
the bash script and the binary against it with the same stubs, and diffs
standard output, standard error, exit status and the log of every stub call.
With `RUN=1` it also runs `--run --yes` on two fresh copies and compares what
each printed and which files are left. Those copies leave out the 1.4 GB
file: APFS can give two identical, freshly written files different block
counts (seen here: 3,024,040 against 3,015,056 for the same 1.5 GB of
zeros), so two copies of it never measure the same, whoever measures them.

```bash
RUN=1 scripts/compare.sh
```

Result: identical, except the "Free space now" line, which moves between two
runs on a live machine and is masked (both values are printed).

## Where the port is stricter than the script

These are corners where the script misbehaves; the Swift version picks the
safer or saner reading.

- Device Support folder names containing a tab or newline broke the script's
  tab-separated rows. They are kept and never listed.
- A DerivedData project name longer than 21 bytes is cut at the last whole
  character, where the script could cut a multibyte character in half.
- A runtime whose `lastUsedAt` doesn't parse made the script abort (`set -u`
  meets `NaN`). It is now simply not flagged as stale.
- With `HOME` unset the script failed with "HOME: unbound variable"; the port
  says "HOME must be your home folder."
- A folder whose contents can't be read, such as the CoreDevice cache when
  macOS denies access to another app's container, is reported with the size
  it could measure, as the script did, and flagged as unknown in the kit
  (`ItemResult.sizeKnown`) so the app can say so instead of showing zero.

## The kit's API

```swift
let engine = try Engine(config: ScanConfig.fromEnvironment(environment), tools: .live(environment: environment))
for await event in engine.scan() { ... }      // ScanEvent: projectFolders, started,
                                              // progress, warning, finished, done, extras
let outcome = await engine.clean(result, mode: .trash)   // or .delete
let restored = await engine.putBack(outcome)
```

`done` arrives once every item is measured; `extras` (installed Xcodes and
simulator runtimes) follows it when the config asks for them. Two events were
added to the sketch in HANDOFF: `projectFolders`, for the line saying which
folders are searched, and `warning`, for the script's warnings.

## What is left

- M5, release: Developer ID signing, notarization, GitHub Releases, the
  Homebrew cask, Sparkle. Not started; `scripts/build-app.sh` only signs ad
  hoc for local use. The bundle id is `com.javilorbada.devclean`.
- Still undecided in HANDOFF section 6: the final app name (DevClean for
  now), icon, a menu
  bar presence, preferences for project folders and the stale-runtime
  threshold (today they come from the same environment variables as the
  CLI, and 90 days), and more scanners.
- The app's own logic (prompts, marks, selection) has no automated tests;
  what it calls in the kit does. It was checked through `scripts/snapshot.sh`.
- Put Back is offered only until the next scan.
