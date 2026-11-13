# Changelog

What changed in each release, newest first. The release workflow takes a
version's notes from its section here, so every change a user would notice
gets a line under Unreleased as it lands.

## Unreleased

- The app writes sizes as Finder and System Settings do, in thousands and
  rounded, so its numbers match the Mac's: a 1 TB disk reads 995 GB, not
  926 GB. The DerivedData growth threshold counts the same way. `devsweep`
  keeps the bash script's report, in 1024s.

## 0.5.0

The first public release. DevSweep shows how much space developer caches
take up on your Mac, from Xcode's DerivedData and old Device Support to
simulators, SwiftPM, Homebrew, npm and Gradle, and cleans what you choose:
to the Trash by default, so anything can be put back. It's a window, a menu
bar item and a command line tool, `devsweep`.

### Highlights
- See where the space went, as a ring or as blocks, and clean what you mark,
  with Put Back.
- Clean part of an item: tick single DerivedData projects or build folders
  in the inspector, and keep the rest.
- See what DevSweep won't clean for you: installed Xcodes, simulator
  runtimes, Android Studio's files and git worktrees, with their sizes and
  what looks unused. A worktree can be removed when nothing in it would be
  lost.
- A menu bar item with the free space, a daily scan, and a notification when
  DerivedData grows past a threshold.
- `devsweep` reports the same items in the terminal, and cleans them with
  `--run`.

### Since 0.1.4
- Cleaning tool caches keeps Playwright MCP's logged-in browser profiles,
  which older versions kept in Playwright's cache folder; only the browsers
  go.
- Each of the three Android screens keeps its own selection.
- Put Back waits while a clean is running.
- The daily scan waits while a clean is asking you something. If a scan
  starts before you answer anyway, nothing is cleaned and the window says so.
- Worktree paths show correctly when your home folder is reached through a
  symlink and its real name has a letter like ö.

### For developers
- The app is split into a view model per screen, four shared models, plain
  values for the numbers and wording, and a coordinator that builds them.
  [docs/architecture.md](docs/architecture.md) draws it.
- Building DevSweep needs Xcode 27 or newer; CI and releases build with
  Xcode 27.2.

## 0.1.4

Preview, November 5, 2026.

- Worktrees are also found through a folder where a tool keeps them: add
  that folder as a project folder, and each worktree in it leads back to its
  repository, wherever that is.
- With no worktrees found, the Worktrees screen says where it looked.

## 0.1.3

Preview, November 4, 2026.

- Deleting for good is about twice as fast on a large DerivedData folder:
  four threads, removing files in the order APFS frees them fastest.
- While an item is deleted for good, its size counts down, and Scan Again
  waits until it's done.
- In the inspector, tick single DerivedData projects or its shared caches,
  or single SwiftPM, Xcode and Gradle build folders, and clean just those,
  with Put Back from the Trash. A project can go while Xcode is open, after
  a question.
- Polish: the panels' controls sit further in from the edges, the hidden
  sidebar's toggle is a plain icon with the title under it, and the main
  buttons' labels are easier to read.

## 0.1.2

Preview, October 30, 2026.

- The sidebar shows how much worktrees can free, and the Worktrees screen
  says how much stays because it holds work.
- The About window shows the right version again.

## 0.1.1

Preview, October 30, 2026. Its About window says 0.1.0.

- A Worktrees screen for the git worktrees of the repositories in your
  project folders, with their size, branch and last commit. It removes one
  only when you ask, with git, and only when nothing in it would be lost;
  the branch stays.
- `devsweep` lists the same worktrees, with the command that removes each.

## 0.1.0

Preview, October 25, 2026. The first build.

### App
- A window that scans your home folder for developer caches, charts them
  as a ring or as blocks, and cleans what you mark: to the Trash by default,
  with Put Back.
- An inspector that says where each item lives, what cleaning it does, and
  what's inside. In a narrow window it floats over the list.
- Lists, without cleaning, installed Xcodes, simulator runtimes, and what
  Android Studio keeps: its installs, the SDK, emulators and Gradle's caches.
- Settings for project folders, items to skip, when something counts as
  unused, how cleaning starts out, and scanning on launch.
- A menu bar item with the free space and a daily scan while the app runs,
  and a notification when DerivedData grows past a threshold.
- Keyboard shortcuts: ⌘1 and ⌘2 for the ring and blocks, ⌥⌘I for the
  inspector, ⌘R to scan again.
- An About window with the version, the license, and where to sponsor or tip.

### Command line
- `devsweep`, a Swift port of the bash script `devclean`, with the same
  flags and safety rules. Run under the script's name, it prints the same
  output, byte for byte.
