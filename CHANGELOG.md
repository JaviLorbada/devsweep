# Changelog

What changed in each release, newest first. The release workflow takes a
version's notes from its section here, so every change a user would notice
gets a line under Unreleased as it lands. A section can end with a Before
and after table of its pull requests' screenshots, which the release page
shows and the update window leaves out.

## Unreleased

- Settings > General has Show in Dock. Turned off, DevSweep leaves the
  Dock and the app switcher when its windows close, and its menu bar item
  opens it again.
- The menu bar item's panel lists About and Check for Updates…, then
  Settings…, then Quit, grouped as in a menu, so a DevSweep out of the
  Dock needs no window to reach them.
- An update the daily check finds no longer opens behind other apps: an
  orange dot sits in the menu bar item's ring, and the same dot leads
  Update Available… at the top of its panel, which brings the update up.
  Once an automatic download is done, the row reads Install Update and
  Relaunch, and installs it. Without the menu bar item, the update window
  opens as before.
- A `.build` folder Xcode builds into, with `-derivedDataPath .build`, is
  listed again. Since 0.7.1 the package clones Xcode keeps in its
  `SourcePackages` kept the whole folder, as if they were work of your own.

### Before and after

| | Before | After |
|---|:---:|:---:|
| Settings > General | <img width="400" alt="Settings' General tab before: Show in menu bar on its own" src="https://github.com/user-attachments/assets/7ff678cd-c8a3-49a4-8b35-3b240836af76" /> | <img width="400" alt="Settings' General tab after: Show in Dock under Show in menu bar" src="https://github.com/user-attachments/assets/50492ebb-057b-4052-b337-5d1703a330cb" /> |
| The menu bar panel | <img width="296" alt="The menu bar panel before: Scan Now and Open DevSweep at the bottom, and nothing under them" src="https://github.com/user-attachments/assets/43b548f6-257c-43e2-836a-36a632b77501" /> | <img width="296" alt="The menu bar panel after: About DevSweep and Check for Updates…, then Settings…, then Quit DevSweep, with separators between the groups" src="https://github.com/user-attachments/assets/fa4233bb-1f6f-4d13-a443-fa86d35776cb" /> |
| The menu bar item, with an update waiting | <img width="400" alt="The menu bar item before, in dark and light menu bars: the ring and the free space" src="https://github.com/user-attachments/assets/4f27d0c3-dd11-4654-acaf-cde9661f658b" /> | <img width="396" alt="The menu bar item with an update waiting, in dark and light menu bars: an orange dot in the middle of the ring" src="https://github.com/user-attachments/assets/5930f9fc-ee40-4994-bba6-da7e6dad3181" /> |
| An update found | | <img width="296" alt="The menu bar panel with an update found: the orange dot leads Update Available…, in its own group at the top" src="https://github.com/user-attachments/assets/93c0211e-cd2e-4ef1-938f-d4a1f521022a" /> |
| An update downloaded | | <img width="296" alt="The menu bar panel with an update downloaded: the orange dot leads Install Update and Relaunch, in its own group at the top" src="https://github.com/user-attachments/assets/f57265cc-ae23-4ad6-bb53-efd9c78d83f7" /> |
| A `.build` Xcode builds into | <img width="400" alt="Before: SwiftPM .build folders (4), without Compass, and 1 note from the scan" src="https://github.com/user-attachments/assets/0000081b-959f-4ecd-9e7a-92f90003cbf2" /> | <img width="400" alt="After: SwiftPM .build folders (5), with Compass's .build at 10 MB, and no note" src="https://github.com/user-attachments/assets/796f8a29-9d18-4f30-ae5e-cd66eae90370" /> |

## 0.7.1

Project build folders that hold work of their own stay where they are.

- A build folder that holds a git repository, like a dependency cloned
  into `node_modules`, is kept with a warning. Your project's repository
  ignores the folder, so it can't see that clone's edits or commits.
  SwiftPM's own clones in `.build/checkouts` and `.build/repositories`,
  and in `.build/index-build` where SourceKit-LSP indexes, don't count:
  `swift package resolve` clones them again.

### Before and after

| | Before | After |
|---|:---:|:---:|
| A `node_modules` with a git repository | <img width="400" alt="Before: node_modules folders (3), the dashboard's included, and no note" src="https://github.com/user-attachments/assets/cc54bd66-31fb-48e3-b7a6-f6492b50eded" /> | <img width="400" alt="After: node_modules folders (2), and a note that the dashboard's node_modules holds a git repository" src="https://github.com/user-attachments/assets/44c13331-2b86-435d-adeb-6c6e90ff2242" /> |

## 0.7.0

DevSweep updates itself from this version on, and finds your projects'
`node_modules`, Pods and Cargo `target` folders. Download this one by hand:
the versions before it have no updater.

- Help > Report a Problem… and Suggest an Idea… open the issue forms on
  GitHub in your browser, with DevSweep's version filled in, and for a
  problem the macOS version too. DevSweep sends nothing itself: you read
  the form and decide whether to submit it.
- `devsweep --version` prints the version and build, as the About window
  writes them, for the bug form's "DevSweep version".
- The app updates itself. Check for Updates… in the DevSweep menu looks
  for a new version, and on its second launch DevSweep asks whether to
  look once a day; Settings > General changes that later, and whether
  updates also install on their own. The update check asks GitHub for the
  latest release, sending only the app's version, and it is the only
  connection DevSweep makes. Versions before this one have no updater:
  download this one by hand, and it updates itself from here on.
- Settings resizes from its edges, and opens tall enough to show General
  whole. A tab taller than the window scrolls, as before.
- Three more items, listed and cleaned per project like `.build` folders:
  `node_modules` next to a `package.json`, CocoaPods' `Pods` next to a
  `Podfile.lock`, and Cargo's `target` next to a `Cargo.toml`. Folders git
  tracks stay. A build folder inside another, like a `node_modules` in
  Gradle's `build` folder, counts as part of the outer one, so nothing is
  counted twice. The app never ticks them on its own; `devsweep --run`
  deletes them with the rest unless you `--skip` them.

### Before and after

| | Before | After |
|---|:---:|:---:|
| The overview | <img width="400" alt="Before: the overview with 11 items" src="https://github.com/user-attachments/assets/f7037bb1-a799-414e-ad79-7f6cb99735a5" /> | <img width="400" alt="After: 14 items, with node_modules folders third biggest and unticked" src="https://github.com/user-attachments/assets/2e2d07fa-f8bb-4f1f-b308-21bf3923d8ed" /> |
| Settings > General | <img width="300" alt="Settings' General tab before the updater" src="https://github.com/user-attachments/assets/553fee22-a17e-4682-a3f0-b739e171c855" /> | <img width="300" alt="Settings' General tab with the daily check for updates on" src="https://github.com/user-attachments/assets/c897839b-7695-4002-a00a-3d650adc309b" /> |
| Settings, as it opens | <img width="400" alt="Before: Settings' General tab as it opens, cut off after Show in menu bar" src="https://github.com/user-attachments/assets/12b7f377-fb2f-40c9-8127-d92dca7b3df9" /> | <img width="400" alt="After: Settings' General tab as it opens, tall enough to show the whole tab, down to the update settings" src="https://github.com/user-attachments/assets/73d29eee-96e1-4bab-876c-744b61b3c05b" /> |
| The second launch | | <img width="420" alt="DevSweep asks whether to check for updates automatically" src="https://github.com/user-attachments/assets/d762682c-0f3a-4d6a-9770-b85f34b3dad1" /> |
| The Help menu | <img width="311" alt="The Help menu before: DevSweep on GitHub, Report a Problem and Support DevSweep" src="https://github.com/user-attachments/assets/cf8b446e-ffa3-4a03-91aa-49c3ec5c6425" /> | <img width="311" alt="The Help menu after: DevSweep on GitHub, Report a Problem…, Suggest an Idea… and Support DevSweep" src="https://github.com/user-attachments/assets/791d6cf0-bf03-4b54-b354-57ef2a01f3aa" /> |
| `devsweep --version` | <img width="400" alt="Before: devsweep --version is an unknown option" src="https://github.com/user-attachments/assets/f9145bbf-b100-46fb-8a12-54a670002347" /> | <img width="363" alt="After: devsweep --version prints devsweep 0.6.0 (202611141450)" src="https://github.com/user-attachments/assets/ec2f1b58-7f25-4ae0-8c59-34dfd0e6d4a4" /> |

## 0.6.0

A new icon, and one way of counting everywhere: simulator runtimes with
the download macOS keeps for them, and the command line as the app counts.

- A new icon: DevSweep's ring of caches floating over a frosted dish, in
  light and dark versions that follow the icon style you choose in macOS 26.
- A simulator runtime's size counts the download macOS keeps for it, which
  removing the runtime removes too: an older runtime such as iOS 18.5 can
  take twice what simctl says. The inspector shows both parts, and the
  command line counts it too.
- The command line writes sizes and free space as the app and Finder do: in
  thousands, rounded, and free space with what macOS frees on its own. Its
  numbers now match the app's. Run as `devclean` it still matches the bash
  script, which counts the same way now.

### Before and after

| | Before | After |
|---|:---:|:---:|
| The icon | | <img width="256" alt="The new icon: DevSweep's five-colour ring floating over a frosted glass dish, on a porcelain tile" src="https://github.com/user-attachments/assets/1b36655c-1321-4840-9b5a-38ecf72e9150" /> |
| A simulator runtime | <img width="400" alt="Before: iOS 18.5 at 8.2 GB, 21.4 GB in 3 runtimes, and no Size section in the inspector" src="https://github.com/user-attachments/assets/3642cdc6-76cf-410d-900e-02b65d88bcbf" /> | <img width="400" alt="After: iOS 18.5 at 17.3 GB, 30.5 GB in 3 runtimes, and the inspector's Size section: 8.2 GB is the runtime, and 9.1 GB a download macOS keeps for it" src="https://github.com/user-attachments/assets/51359311-28f2-4031-828e-04de01bee4a9" /> |
| The command line | <img width="400" alt="Before: sizes in 1024s, DerivedData 18.5 GB, Total 33.5 GB, Free space now 320.2 GB" src="https://github.com/user-attachments/assets/eb42e326-7e98-49df-a4fe-8c6e25127984" /> | <img width="400" alt="After: sizes in thousands, DerivedData 20.2 GB, Total 36.3 GB, Free space now 354.2 GB, as the app shows them" src="https://github.com/user-attachments/assets/b12a4ae6-d516-430c-b1fe-7273aa9b2418" /> |

## 0.5.1

The app's numbers now match your Mac's.

- The app writes sizes as Finder and System Settings do, in thousands and
  rounded, so its numbers match the Mac's: a 1 TB disk reads 995 GB, not
  926 GB. The DerivedData growth threshold counts the same way. `devsweep`
  keeps the bash script's report, in 1024s.
- Free space is what Finder and System Settings show: it counts the space
  macOS frees on its own, such as local snapshots, and the menu reads
  "337.6 GB free of 995 GB".

### Before and after

| | Before | After |
|---|:---:|:---:|
| The menu bar | <img width="296" alt="Before: the menu bar reads 381.7 GB, and the panel 381.7 GB free" src="https://github.com/user-attachments/assets/a8d218cc-b7f2-4969-bb42-65e665afc9ae" /> | <img width="296" alt="After: the menu bar reads 389.0 GB, and the panel 389.0 GB free of 995 GB" src="https://github.com/user-attachments/assets/8e7781d5-42cc-4e60-bd08-674389f71b89" /> |

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
