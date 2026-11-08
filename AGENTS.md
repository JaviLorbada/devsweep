# Repository Guidelines

## Layout
- `Sources/DevSweepKit`: scanning, measuring, the path policy, cleaning and the report. No AppKit except where a macOS API needs it.
- `Sources/devsweep`: the command line tool. Run under the original script's name, `devclean`, its output is the bash script's, byte for byte.
- `Sources/DevSweepApp`: the SwiftUI app: the window, Settings and the menu bar item, with its models and view models.
- `Tests/DevSweepKitTests`, `Tests/DevSweepAppTests`: Swift Testing. Fixtures in `Tests/DevSweepKitTests/Fixtures`.
- `Scripts`: packaging, lint, release, the parity checks and the debug captures.
- `docs`: architecture, development, packaging, releasing, the original design.

## App architecture
- `docs/architecture.md` draws it, and the README shows its first diagram. The diagrams change in the same commit as the code they draw.
- `AppCoordinator` builds the dependencies and every model, and wires one model's events to the others. No view reads it; the scenes put its models in the environment with `environment(models:)`.
- Shared models hold what several screens read: `ScanModel` (the rows, the scan, the listings, the last scan; only it changes the rows), `CleaningModel`, `MarksModel`, `RunningAppsModel`. Only they call the kit.
- A view model per screen holds what that screen owns: `WindowViewModel`, `OverviewViewModel`, `XcodesViewModel`, `RuntimesViewModel`, `WorktreesViewModel`, `AndroidViewModel`. They call the shared models, never the kit.
- Numbers and words are plain values, tested without a model: `Tally`, `StatusText`, `CleanPrompt`.
- A view takes from the environment only the models it reads; rows, cells and ring segments take values.
- State is `private(set)`. Only what a view binds stays settable (the screen, the chart, the Trash toggle, an open sheet); everything else changes through a method named for what it does.
- New state goes in the model that owns it. No model grows into the app: past SwiftLint's limits, it splits.
- Each model and view model has its own test file, named after it.

## Build, test, lint
- `make build`, `make test` (Swift Testing, in parallel), `make lint` (strict), `make format`.
- `make acceptance DOTFILES=<dotfiles checkout>`: the bash script's bats suite against the binary, then both side by side on a fake home.
- `make app` packages `build/DevSweep.app`; `make release` zips the tool and the app into `dist/`.
- Swift 6 strict concurrency and zero warnings. swift-argument-parser is the only dependency; ask before adding one.

## Safety rule
- Never run the tool or the app in `--run` or any deleting mode against a real home folder. Report mode is fine.
- Deletion is exercised only in tests, against a fake home in a temp folder, with fake tools, so simctl and brew never really run.
- Never pass `--yes` outside tests.
- Never delete, move or trash anything under `~/Library` by hand.

## Commits
- Imperative subject line, a short body saying why. One coherent change per commit, with tests passing.
- Automation never pushes; the maintainer does.

## Tests
- Swift Testing, with backticked sentence names: ``@Test func `skips folders git tracks`()``.
- Every test makes its own temp folder and fakes what has side effects through `Dependencies` and the app's seams (`AppQuitting`, the preferences, scan memory and notification stores). Nothing shared, nothing `.serialized`; `swift test --parallel` must pass.
- No stubs on `PATH` in Swift tests. They belong to the bats suite, which runs the built binary as a user would.
- The bats suite is the acceptance test: 52 of 52, and `Scripts/compare.sh` identical.

## Pull requests
- What changed and why, and the commands run: `make lint test acceptance`.
- Screenshots for window changes, from `WIDTH=1280 Scripts/snapshot.sh`.
- A line under Unreleased in `CHANGELOG.md` for anything a user would notice, and README.md kept current.
