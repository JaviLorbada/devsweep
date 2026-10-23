# The original design

The mockup the app was built from: `Main.dc.html` (the overview), `Scanning.dc.html`
(the scan in progress) and `Extras.dc.html` (runtimes and Xcodes), with the canvas
they were laid out on in `canvas.json`. Open the HTML files in a browser.

## Window

About 1280 by 860 points, three panes: a sidebar, the center and an inspector.

- **Sidebar** (232 points): Overview; Caches with the five families, each with a
  colored dot and its size; Also worth a look with the extras; at the bottom a
  meter for the boot volume in three parts: used, reclaimable in blue, free.
- **Center**: the screen's title with a status line ("Scanned just now, 11 items.
  Xcode and Simulator are closed."), a Ring or Blocks control, and Scan Again,
  which turns into Stop while scanning, next to a capsule saying "Measuring
  <item>" over a thin progress bar. Below: the chart card, the items table, and a
  footer with the Move to Trash checkbox, what is marked, and the primary
  "Clean 35.5 GB" button.
- **Ring**: two concentric rings, families inside and their items outside, about
  2 degrees between segments, the reclaimable total in the hole. To the right a
  thin stacked family bar and a legend with share and size.
- **Blocks**: a squarified treemap of the live items in the same card; cells
  tinted with the item's color at 30 percent and bordered at 60, labeled when
  big enough; the selected cell at 55 percent with a solid border.
- **Items table**: mark, color dot, name with its family in muted text, a 120
  point bar, the size in tabular figures, and Clean. Rows show Measuring
  (pulsing) or Waiting during a scan and In Trash after cleaning. Selecting a
  row highlights its ring segment and dims the others.
- **Inspector** (300 points): family eyebrow, the item's name, its size with a
  state word, Where (the path and Reveal in Finder), What happens, and for
  DerivedData what is inside: the compilation and module caches and each project
  with its last build and a "project gone" badge. At the bottom Clean <item>,
  Put Back, or a disabled Measuring.
- **Runtimes**: rows with last use, a thin bar and size; flagged rows say why.
  The inspector explains the flag, what removing does, the exact simctl
  command, and Remove Runtime. Xcode versions below with Reveal in Finder, and a
  note that Archives are never listed.

## Families and colors

Five families, five hues; each family's items are steps of its hue, largest
first from darker to lighter. Beyond about seven colors neighbouring classes
stop being told apart. Colors are for marks only: dots, rings, bars and cells.
Everything else uses system materials and semantic colors. Every segment also
has a labeled legend row and a table row, which is what makes the three light
hues below 3:1 on white acceptable.

| Family | Dark | Light | Items, darker to lighter |
|---|---|---|---|
| Xcode | `#3987E5` | `#2A78D6` | DerivedData, Old Device Support, Simulators, Xcode build folders, Device install cache |
| Swift packages | `#D95926` | `#EB6834` | SwiftPM package cache, `.build` folders |
| Homebrew | `#199E70` | `#1BAF7A` | Homebrew |
| npm | `#C98500` | `#EDA100` | npm cache |
| Other tools | `#D55181` | `#E87BA4` | Tool caches, Gradle build folders |

The per-item steps are in `Sources/DevSweepApp/Palette.swift`.

## The scan

Items fill in as they are measured. Unmeasured segments are drawn in a faint
tone so the ring is whole from the start; the hero number, the sidebar and the
disk meter count up live; treemap cells slide into place over 0.4 seconds; the
row being measured pulses. With Reduce Motion on, all of it stands still.

## Since the mockup

- The columns are rounded panels on a darker window background, next to the
  system's floating sidebar, with an 8 point gap.
- The scan controls moved from the toolbar into the center panel's header, as
  glass controls: Ring or Blocks as a glass pill with the selected segment
  raised. Only the inspector toggle stays in the toolbar.
- Table rows select edge to edge, as macOS tables do.
- Also worth a look groups the extras under Xcode and Android Studio; the latter
  lists Android Studio's installs, the SDK, emulators and Gradle's caches.
- Muted text has its own color, 4.6:1 or more on every surface.
- A menu bar item shows the free space and what the last scan found.
