# Design

How the app uses color and motion. The window itself is in the README's
screenshot, and [architecture.md](architecture.md) has how it's built.

## Families and colors

Five families, five hues; each family's items are steps of its hue, largest
first from darker to lighter. Beyond about seven colors, neighbouring
classes stop being told apart. Colors are for marks only: dots, rings, bars
and cells. Everything else uses system materials and semantic colors. Every
segment also has a labeled legend row and a table row, which is what makes
the three light hues below 3:1 on white acceptable. Muted text has its own
color, 4.6:1 or more on every surface.

| Family | Dark | Light | Items, darker to lighter |
|---|---|---|---|
| Xcode | `#3987E5` | `#2A78D6` | DerivedData, Old Device Support, Simulators, Xcode build folders, Device install cache |
| Swift packages | `#D95926` | `#EB6834` | SwiftPM package cache, `.build` folders |
| Homebrew | `#199E70` | `#1BAF7A` | Homebrew |
| npm | `#C98500` | `#EDA100` | npm cache |
| Other tools | `#D55181` | `#E87BA4` | Tool caches, Gradle build folders |

The per-item steps are in `Sources/DevSweepApp/Views/Style/Palette.swift`.

## The scan

Items fill in as they are measured. Unmeasured segments are drawn in a
faint tone so the ring is whole from the start; the total, the sidebar and
the disk meter count up live; the blocks slide into place over 0.4 seconds;
the row being measured pulses. With Reduce Motion on, all of it stands
still.
