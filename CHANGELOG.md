# Changelog

What changed in each release, newest first. The release workflow takes a
version's notes from its section here, so every user-visible change gets a
line under Unreleased as it lands.

## Unreleased

### Command line
- `devsweep`, a Swift port of the bash script `devclean` with the same flags
  and safety rules; run under the script's name it prints the same output,
  byte for byte.

### App
- A window that scans the home folder, charts what each cache holds as a ring
  or blocks, and cleans what is marked, to the Trash by default with Put Back.
- Lists, without cleaning, installed Xcodes, simulator runtimes and what
  Android Studio keeps: its installs, the SDK, emulators and Gradle's caches.
- Settings for project folders, items to skip, the unused threshold, how
  cleaning starts out and scanning on launch.
- A menu bar item with the free space, a daily scan while the app runs, and a
  notification when DerivedData grows past a threshold.
