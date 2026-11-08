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
  folders, and of those a project folder of worktrees leads to, with the
  command that removes each one with nothing to lose.
- Deleting for good shares the work between four threads and removes each
  folder's files in the order APFS frees them fastest: about twice as fast
  as `FileManager` on a large DerivedData folder.

### App
- A window that scans the home folder, charts what each cache holds as a ring
  or blocks (small caches drawn larger so they stay visible, with their exact
  sizes in the labels), and cleans what is marked, to the Trash by default
  with Put Back. In a window too narrow for the inspector beside the
  center, the inspector floats over it, and the sidebar narrows rather than
  being cut off. While an item is deleted for good, its size counts down
  and its row shows how far it has got, and Scan Again and Put Back wait
  until cleaning is done. The daily scan waits, too, while a clean's
  question is open; a scan started before the answer leaves nothing
  cleaned, and the window says so. The controls along the panels' top and bottom
  edges sit 16 points in from them, the hidden sidebar's toggle is a plain
  icon with the title on its own line under it, and the main buttons'
  labels are white on a deeper accent color.
- DerivedData's projects and shared caches, and each SwiftPM, Xcode and
  Gradle build folder, can be ticked in the inspector and cleaned on their
  own, with Put Back from the Trash. A project can go while Xcode is open,
  after a question; the shared caches ask to quit Xcode, as the whole
  folder does. Past the five largest projects or folders, the rest open to
  show each.
- Lists, without cleaning, installed Xcodes, simulator runtimes and what
  Android Studio keeps: its installs, the SDK, emulators and Gradle's caches.
  Each of the three Android screens keeps its own selection.
- A Worktrees screen for the git worktrees of the repositories in the project
  folders, wherever they live, with their size, branch and last commit. It
  removes one only when asked, with git, and only when nothing in it would
  be lost; the branch stays. The sidebar's size is what can go, and the
  screen says how much stays because it holds work. A folder where a tool
  keeps its worktrees can be a project folder too: each worktree in it
  leads back to its repository, wherever that is.
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
