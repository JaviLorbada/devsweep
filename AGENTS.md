# Repository Guidelines

## Layout
- `Sources/DevCleanKit`: scanning, measuring, the path policy, cleaning and the report. No AppKit except where a macOS API needs it.
- `Sources/devclean`: the command line tool. Its output is the bash script's, byte for byte.
- `Sources/DevCleanApp`: the SwiftUI app: the window, Settings and the menu bar item.
- `Tests/DevCleanKitTests`, `Tests/DevCleanAppTests`: Swift Testing. Fixtures in `Tests/DevCleanKitTests/Fixtures`.
- `Scripts`: packaging, lint, release, the parity checks and the debug captures.
- `docs`: architecture, development, packaging, releasing, the original design.

## Build, test, lint
- `make build`, `make test` (Swift Testing, in parallel), `make lint` (strict), `make format`.
- `make acceptance DOTFILES=<dotfiles checkout>`: the bash script's bats suite against the binary, then both side by side on a fake home.
- `make app` packages `build/DevClean.app`; `make release` zips the tool and the app into `dist/`.
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
- Every test makes its own temp folder and fakes what has side effects through `Dependencies`. Nothing shared, nothing `.serialized`; `swift test --parallel` must pass.
- No stubs on `PATH` in Swift tests. They belong to the bats suite, which runs the built binary as a user would.
- The bats suite is the acceptance test: 52 of 52, and `Scripts/compare.sh` identical.

## Pull requests
- What changed and why, and the commands run: `make lint test acceptance`.
- Screenshots for window changes, from `WIDTH=1280 Scripts/snapshot.sh`.
- A line under Unreleased in `CHANGELOG.md` for anything a user would notice, and README.md kept current.
