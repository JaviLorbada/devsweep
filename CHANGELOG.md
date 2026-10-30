# Changelog

What changed in each release, newest first. The release workflow takes a
version's notes from its section here, so every user-visible change gets a
line under Unreleased as it lands.

## Unreleased

### Command line
- `devsweep`, a Swift port of the bash script `devclean` with the same flags
  and safety rules; run under the script's name it prints the same output,
  byte for byte.
- `devsweep` lists the git worktrees of the repositories in the project
  folders, and the command that removes each one with nothing to lose.

### App
- A window that scans the home folder, charts what each cache holds as a ring
  or blocks (small caches drawn larger so they stay visible, with their exact
  sizes in the labels), and cleans what is marked, to the Trash by default
  with Put Back. In a window too narrow for the inspector beside the
  center, the inspector floats over it, and the sidebar narrows rather than
  being cut off.
- Lists, without cleaning, installed Xcodes, simulator runtimes and what
  Android Studio keeps: its installs, the SDK, emulators and Gradle's caches.
- A Worktrees screen for the git worktrees of the repositories in the project
  folders, wherever they live, with their size, branch and last commit. It
  removes one only when asked, with git, and only when nothing in it would
  be lost; the branch stays.
- Settings for project folders, items to skip, the unused threshold, how
  cleaning starts out and scanning on launch.
- A menu bar item with the icon's ring and the free space, a daily scan while
  the app runs, and a notification when DerivedData grows past a threshold; a
  setting hides it.
- An About window with the version, links to the source and the MIT license,
  where to sponsor or tip, and acknowledgements.
- Keyboard shortcuts: ⌘1 and ⌘2 for the ring and blocks, ⌥⌘I for the
  inspector and ⌘R to scan again, and a Help menu linking to the project, its
  issues and its tip jar.
