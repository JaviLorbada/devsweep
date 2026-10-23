# Architecture

One Swift package, three products:

| Target | What it is |
|---|---|
| `DevSweepKit` | Scanning, measuring, the path policy, cleaning, the report. No AppKit except where a macOS API needs it (the Trash). |
| `devsweep` | The command line tool on top of the kit. Run under the original script's name, `devclean`, it behaves as the bash script, byte for byte. |
| `DevSweepApp` | The SwiftUI app: the window, Settings and the menu bar item. |

## The scan

`Engine` scans one home folder. `Engine.scan(_:)` returns an `AsyncStream<ScanEvent>`:
the project folders it searches, then each item `started`, its `progress` and
`finished`, `done` with the total, and then the extras (installed Xcodes and
simulator runtimes) and, when the app asks for it, what Android Studio keeps.
The command line scans one item at a time in report order (`ScanOptions.report`);
the app scans four at a time, quickest first (`ScanOptions.interactive`).

Each item has a `Scanner`: it lists the folders the item would delete, each
through the path policy, and measures them the way `du -sk` does. Groups the
app lists but never cleans, like Android Studio's, have a `ListingScanner`:
the same contract with a listing for a result, so a clean step can be added
later without touching the command line's items.

`PathPolicy` is the safety rule in code: a path is acted on only when it is a
directory, not itself a symlink, and resolves strictly inside the resolved
home folder, checked when it is listed and again right before it goes.

## Seams

Everything with a side effect sits behind a protocol, so tests run it fake.
The kit's public entry points, `Engine.init(config:dependencies:)` and
`CommandLineSession.run(_:environment:dependencies:terminal:)`, take one
`Dependencies` value:

| Seam | Protocol | Live | In tests |
|---|---|---|---|
| Processes: simctl, brew, defaults, xcode-select, git | `SimctlClient`, `BrewClient`, `XcodeDefaultsReading`, `XcodeSelectReading`, `GitClient`, over `ProcessRunner` | Found through `PATH` | `FakeTools` records calls and answers |
| Spotlight's last-used dates (mdls) | `LastUsedDateReading` | `SpotlightLastUsedDates` | A dictionary |
| Running apps | `RunningAppsChecking` | `PgrepRunningApps`; the app's `WorkspaceRunningApps` | A set |
| The Trash | `TrashService` | `SystemTrash` | `FolderTrash`, a folder inside the temp home |
| Files: list, attributes, read, remove | `FileSystemAccess` | `LiveFileSystem` | The temp folder itself, or a recording fake |
| The time | `WallClock` | `SystemClock` | `FixedClock` |

`Dependencies.live(environment:)` builds the real one; `Tools.unavailable` is
a machine with none of the tools, which the app's tests use. The path policy
and the `du`-style measurer stay on the real disk on purpose: they are the
safety rule and the numbers the report must match, and each test gets its
own temp folder to run them against.

The app adds its own:

| Seam | Protocol | Live | In tests |
|---|---|---|---|
| Preferences | `PreferencesStore` | `UserDefaults.standard` | `InMemoryPreferencesStore` |
| The last scan | `ScanMemoryStore` (kit) | `ScanStore`, a JSON file in Application Support | `InMemoryScanStore`, or the file in a temp home |
| Notifications | `NotificationPoster` | `UserNotificationPoster` | `SilentNotificationPoster`, a recording poster |

No Swift test puts a stub on `PATH`; stubs on `PATH` live only in the bats
suite, which runs the built binary as a user would.

## The window

`AppModel` (`@Observable`, main actor) turns scan events into rows and owns
selection, marks, cleaning and Put Back. Views read it from the environment.
Layout decisions that depend on width are made inside a `GeometryReader`
with a fixed height, so no view's minimum size follows the width it last had;
`WindowLayout` holds the column sizes the layout tests check every screen
against.

## Tests

- Swift Testing for the kit and the app, run in parallel: every test makes its
  own temp folder and fakes; nothing is shared between tests.
- The bats suite from the dotfiles repository, run against the binary: the
  acceptance test that the tool behaves as the bash script did.
- `Scripts/compare.sh` runs the bash script and the binary side by side on
  the same fake home and diffs output, exit status, tool calls and what is left.
