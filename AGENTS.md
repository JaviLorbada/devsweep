# Repository Guidelines

## Layout
- `Sources/DevSweepKit`: scanning, measuring, the path policy, cleaning and the report. No AppKit except where a macOS API needs it.
- `Sources/devsweep`: the command line tool. Run under the original script's name, `devclean`, its output is the bash script's, byte for byte.
- `Sources/DevSweepApp`: the SwiftUI app: the window, Settings and the menu bar item. A folder per kind of piece: `App`, `Protocols`, `Models`, `ViewModels`, `Values`, `Views` (a folder per screen), `System`, `Debug`.
- `Tests/DevSweepKitTests`, `Tests/DevSweepAppTests`: Swift Testing. The app's tests use the app's folders. Fixtures in `Tests/DevSweepKitTests/Fixtures`.
- `Scripts`: packaging, lint, release, the parity checks and the debug captures.
- `docs`: architecture, design, development, packaging, parity with the bash script, releasing.

## App architecture
- `docs/architecture.md` draws it, and the README shows its first diagram. The diagrams change in the same commit as the code they draw.
- `AppCoordinator` builds the dependencies and every model, and wires one model's events to the others. No view reads it; the scenes put its models in the environment with `environment(models:)`.
- Shared models hold what several screens read: `ScanModel` (the rows, the scan, the listings, the last scan; only it changes the rows), `CleaningModel`, `MarksModel`, `RunningAppsModel`. Only they call the kit.
- A view model per screen holds what that screen owns: `WindowViewModel`, `OverviewViewModel`, `XcodesViewModel`, `RuntimesViewModel`, `WorktreesViewModel`, `AndroidViewModel`. They call the shared models, never the kit.
- Models and view models take each other through the protocols in `Protocols`, each named for what its user reads: `ScanResults`, `Listings`, `ScanRows`, `Marking`, `RunningApps`, `CleaningTotals`, `Navigation`; and `Cleaner`, the kit's engine as a clean sees it, which only taking the rows hands out. Only `AppCoordinator` names the classes. `Preferences` is passed as it is.
- No protocol for the coordinator, which nothing depends on, or for a view model as its views see it: views take the class from the environment.
- Numbers and words are plain values, tested without a model: `Tally`, `StatusText`, `CleanPrompt`.
- A view takes from the environment only the models it reads; rows, cells and ring segments take values.
- State is `private(set)`. Only what a view binds stays settable (the screen, the chart, the Trash toggle, an open sheet); everything else changes through a method named for what it does.
- New state goes in the model that owns it. No model grows into the app: past SwiftLint's limits, it splits.
- A new file goes in its kind's folder; a new screen gets a folder under `Views`, its view model goes in `ViewModels`, and its tests in the same folders under `Tests`.
- Each model and view model has its own test file, named after it, that builds it with fakes for the protocols it takes (`Tests/DevSweepAppTests/Support/Fakes.swift`). Only the coordinator's tests, the end-to-end tests in `Flows` and the view tests build the whole app.

## Build, test, lint
- `make build`, `make test` (Swift Testing, in parallel), `make lint` (strict), `make format`.
- `make acceptance DOTFILES=<dotfiles checkout>`: the bash script's bats suite against the binary, then both side by side on a fake home.
- `make app` packages `build/DevSweep Dev.app`, a development build with its own name, icon, bundle id and data, so it runs beside the released app; `make release` zips the tool and the released app into `dist/`.
- Swift 6 strict concurrency and zero warnings. The dependencies are swift-argument-parser, for the tool, and Sparkle, which updates the app; ask before adding one.

## Safety rule
- Never run the tool or the app in `--run` or any deleting mode against a real home folder. Report mode is fine.
- Deletion is exercised only in tests, against a fake home in a temp folder, with fake tools, so simctl and brew never really run.
- Never pass `--yes` outside tests.
- Never delete, move or trash anything under `~/Library` by hand.

## Commits
- Imperative subject line, a short body saying why. One coherent change per commit, with tests passing.
- Changes land through pull requests that pass CI. Pushes and merges happen when the maintainer says so.

## Tests
- Swift Testing, with backticked sentence names: ``@Test func `skips folders git tracks`()``.
- Every test makes its own temp folder and fakes what has side effects through `Dependencies` and the app's seams (`AppQuitting`, the preferences, scan memory and notification stores), and the other models through their protocols. Nothing shared, nothing `.serialized`; `swift test --parallel` must pass.
- No stubs on `PATH` in Swift tests. They belong to the bats suite, which runs the built binary as a user would.
- The bats suite is the acceptance test: 57 of 57, and `Scripts/compare.sh` identical.

## Pull requests
- What changed and why, and the commands run: `make lint test acceptance`.
- Screenshots for window changes, from `WIDTH=1280 Scripts/snapshot.sh`, and for menu bar changes, from `Scripts/snapshot.sh <folder> menubar-light`, before and after.
- A line under Unreleased in `CHANGELOG.md` for anything a user would notice, and README.md kept current.
