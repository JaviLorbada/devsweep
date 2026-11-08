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

Deleting for good goes through `TreeRemover`, about twice as fast as
`FileManager` on a DerivedData folder: four threads share the walk, and each
directory's files go in the order of their inode numbers, which APFS
removes fastest. Every step starts from the folder's parent, opened once,
and refuses a symlink anywhere along the path (`O_NOFOLLOW_ANY`), so the
walk can't be led out of the folder; directories are listed with
`getattrlistbulk`, which gives each file's size for the progress as well.
Whatever it can't remove, `FileManager` tries again and says why.

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
| Quitting Xcode and Simulator | `AppQuitting` | `WorkspaceAppQuitter`, as choosing Quit would | `FakeDeveloperApps`, which also says what runs |

No Swift test puts a stub on `PATH`; stubs on `PATH` live only in the bats
suite, which runs the built binary as a user would.

## The app

The kit is the domain and the data: its model types are the entities,
`Engine`'s methods the use cases, the scanners, `PathPolicy` and the cleaner
the rules, and `Dependencies` the ports, live or fake. The app is MVVM on
Observation, in four kinds of piece:

- **Shared models** hold what several screens read, once.
- **View models**, one per screen, hold what that screen owns.
- **Plain values** work out the numbers and the words, with nothing to observe.
- **`AppCoordinator`** builds them all and wires one model's events to the others.

```mermaid
flowchart TB
  subgraph Views["Views · SwiftUI"]
    direction LR
    Screens["Overview · Xcodes · Runtimes<br/>Worktrees · Android"]
    Chrome["Sidebar · header · inspector<br/>menu bar · Settings"]
  end

  subgraph ViewModels["View models · one per screen"]
    direction LR
    WindowVM[WindowViewModel]
    OverviewVM[OverviewViewModel]
    XcodesVM[XcodesViewModel]
    RuntimesVM[RuntimesViewModel]
    WorktreesVM[WorktreesViewModel]
    AndroidVM[AndroidViewModel]
  end

  subgraph Models["Shared models · one source of truth"]
    direction LR
    Scan[ScanModel]
    Cleaning[CleaningModel]
    Marks[MarksModel]
    Apps[RunningAppsModel]
  end

  subgraph Kit["DevSweepKit"]
    Engine
    Rules["Scanners · PathPolicy<br/>SizeMeasurer · Cleaner"]
    Deps["Dependencies<br/>live, or fake in tests"]
  end

  Coordinator["AppCoordinator<br/>builds the models and wires them"]
  Values["Tally · StatusText · CleanPrompt<br/>numbers and words, as plain values"]
  Seams["App seams<br/>preferences · last scan · notifications · quitting"]
  CLI["devsweep<br/>command line"]
  Mac[("macOS<br/>files · Trash · simctl · brew · git")]

  Views -->|"read state, call methods"| ViewModels
  Views -->|"read state, call methods"| Models
  ViewModels --> Models
  ViewModels -.-> Values
  Models -.-> Values
  Models -->|"async calls, scan events back"| Engine
  Models --> Seams
  CLI --> Engine
  Engine --> Rules
  Rules --> Deps
  Deps --> Mac
  Coordinator -.->|creates| ViewModels
  Coordinator -.->|creates| Models
```

Arrows point the way calls go; state comes back up through Observation.
Views call view models and shared models; view models call shared models;
only shared models call the kit, and only the kit touches macOS. No view
reads the coordinator: the scenes put its models in the environment with
`environment(models:)`, and each view takes only those it reads. Rows,
cells and ring segments take plain values.

| Type | What it owns | Who uses it |
|---|---|---|
| `WindowViewModel` | The screen on show, Ring or Blocks, whether the inspector shows and where. | Sidebar, header, the View menu |
| `OverviewViewModel` | The selected item, picking a family, the status line. | Ring, Blocks, items list, inspector |
| `XcodesViewModel` | The selected Xcode and the screen's subtitle. | Xcode versions |
| `RuntimesViewModel` | The selected runtime, its removal sheet, the subtitle. | Simulator runtimes |
| `WorktreesViewModel` | The selected worktree, its removal sheet, the subtitle, the git command. | Worktrees |
| `AndroidViewModel` | A selection for each Android screen, their lists and subtitles. | The three Android screens |
| `Removal` | One removal sheet's state: what is waiting, whether it runs, why it failed. | Runtimes, worktrees |
| `ScanModel` | The rows, one per item, and the scan that fills them; the listings, the free space, the last scan kept for the next launch. Only it changes the rows, and a scan and a clean never run at once. | Every screen, the menu bar, `CleaningModel` |
| `CleaningModel` | A clean from the question to the end: quitting Xcode, confirming, the Trash or deleting, Put Back, cleaning parts, this session's totals, the notices. | Overview footer, items list, inspector, the window's alerts |
| `MarksModel` | What is ticked, items and parts, and the three biggest ticked by default. | Items list, inspector, `CleaningModel` |
| `RunningAppsModel` | Whether Xcode and Simulator are open, and quitting them. | `CleaningModel`, the status line |
| `Tally` | Row order, totals, each family's share, the ring's weights. | `ScanModel`, the charts, the sidebar |
| `StatusText` | The status lines, the subtitles' words, "3 minutes ago". | The view models, the menu bar |
| `CleanPrompt` | The questions' words, by name up to three and by count past that. | `CleaningModel`, the window's alerts |
| `AppCoordinator` | Builds everything; wires a scan's start and end to the marks, the selection and the growth check; the half-minute tick and the daily scan. | The app's scenes and menus |

State is `private(set)`. What a view binds stays settable (the screen, the
chart, the Trash toggle, an open sheet); everything else changes through a
method named for what it does: `select(_:)`, `askToRemove(_:)`,
`requestClean(_:)`.

### A scan

```mermaid
sequenceDiagram
  actor You
  participant Header as CenterHeader
  participant Scan as ScanModel
  participant Engine
  participant Coordinator as AppCoordinator
  You->>Header: Scan Again
  Header->>Scan: scan()
  Scan->>Coordinator: onStart
  Coordinator->>Coordinator: clear the marks and the last parts cleans
  Scan->>Engine: scan(.interactive)
  loop each item, four at a time
    Engine-->>Scan: started, progress, finished
    Scan-->>Header: the rows change, views redraw
  end
  Engine-->>Scan: done
  Scan->>Coordinator: onItemsMeasured
  Coordinator->>Coordinator: tick the three biggest, select the first
  Engine-->>Scan: extras, then Android
  Scan->>Scan: keep it for the next launch
  Scan->>Coordinator: onFinished
  Coordinator->>Coordinator: DerivedData grew past the threshold? Notify
```

### A clean

```mermaid
sequenceDiagram
  actor You
  participant Window as The window
  participant Cleaning as CleaningModel
  participant Apps as RunningAppsModel
  participant Scan as ScanModel
  participant Engine
  You->>Window: Clean the marked items
  Window->>Cleaning: requestClean(items)
  Cleaning->>Apps: refresh()
  alt Xcode is open and an item needs it closed
    Cleaning-->>Window: pendingClean, quit Xcode and Simulator?
    You->>Window: Quit and Clean
    Window->>Cleaning: quitAppsAndClean(pending)
    Cleaning->>Apps: quit(apps)
  end
  opt deleting for good, or simctl or brew removes it
    Cleaning-->>Window: pendingClean, confirm?
    You->>Window: Clean
    Window->>Cleaning: confirmClean(pending)
  end
  Cleaning->>Scan: beginCleaning()
  loop each item
    Cleaning->>Engine: clean(result, mode)
    Engine-->>Cleaning: removed so far
    Cleaning->>Scan: cleaningProgress, the row counts down
    Cleaning->>Scan: finishCleaning(item, outcome)
  end
  Cleaning->>Scan: endCleaning(warnings:), kept for the next launch
```

### Layout

Layout decisions that depend on width are made inside a `GeometryReader`
with a fixed height, so no view's minimum size follows the width it last had;
`WindowLayout` holds the column sizes the layout tests check every screen
against.

## Tests

- Swift Testing for the kit and the app, run in parallel: every test makes its
  own temp folder and fakes; nothing is shared between tests.
- In the app, each model and view model has its own test file, named after
  it; `Tally`, `StatusText` and `CleanPrompt` are checked without a model.
- The bats suite from the dotfiles repository, run against the binary: the
  acceptance test that the tool behaves as the bash script did.
- `Scripts/compare.sh` runs the bash script and the binary side by side on
  the same fake home and diffs output, exit status, tool calls and what is left.
