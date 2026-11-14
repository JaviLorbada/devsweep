# Packaging

The repository is SwiftPM only; there is no Xcode project. To work in Xcode,
open `Package.swift`: Xcode keeps its workspace in
`.swiftpm/xcode/package.xcworkspace`, which stays out of git.

## The app

```bash
Scripts/package_app.sh          # release build into build/DevSweep Dev.app
Scripts/package_app.sh debug    # debug build, with the debug-only harnesses
```

Both are development builds: DevSweep Dev, with its own icon
(`docs/icon/development/AppIcon.icon`), the bundle id
`com.javilorbada.devsweep.dev`, and its own settings and last scan
(`~/Library/Application Support/DevSweep Dev`), so one runs beside the
DevSweep you installed and neither touches the other's. Only
`Scripts/build_release.sh` packages the app people download, with
`FOR_RELEASE=1`: DevSweep, its bundle id and icon.

The debug build goes to `build/debug/DevSweep Dev.app` with the bundle id
`com.javilorbada.devsweep.debug`. `Scripts/snapshot.sh` uses it, so
captures never replace the bundle you open, and its settings stay apart
from the release build's.

The script builds the `DevSweepApp` executable and wraps it in a bundle:

- **Info.plist** gets the bundle id, name and version from `version.env`:
  `PRODUCT_NAME`, `BUNDLE_ID`, `MARKETING_VERSION` and `BUILD_NUMBER`. Change
  them there, never in the plist. `ProductInfo.swift` holds the same names for
  the code, and a test fails when the two disagree.
- **Which build it is** goes in the plist too: `DevSweepCommit`, the short
  commit; `DevSweepTreeDirty`, whether the tree had uncommitted changes;
  `DevSweepReleaseSigned`, whether it was signed with a Developer ID; and
  `DevSweepDevelopment`, whether it is a development build. About
  shows the commit, and so does the overview's status line unless the build
  is signed for release. `defaults read <bundle>/Contents/Info DevSweepCommit`
  reads it from outside.
- **The icon** is an Icon Composer file, `docs/icon/AppIcon.icon`: a frosted
  dish and the ring of the five families as separate layers, each with a
  light and a dark version, over a porcelain or indigo fill. The development
  build's, `docs/icon/development/AppIcon.icon`, is a blueprint of the same
  ring and dish in white line art on a graphite grid, labelled DEV. `Scripts/compile_icon.sh`
  compiles one with Xcode's `actool` into `Assets.car`, where macOS 26 finds
  the layers and draws the light, dark, clear and tinted appearances, and a
  flat `AppIcon.icns`; the plist names both as `AppIcon`. Open the file in
  Icon Composer (in Xcode's Applications) to change it.
  `swift Scripts/render_icon.swift <icon> <png> [side] [light|dark]` draws it
  into a PNG as Finder shows it, with Icon Composer's renderer: `AppIcon.png`
  for the social preview, and the README's `readme-light.png` and
  `readme-dark.png` at 256 pixels.
- **Sparkle**, which updates the app, goes in `Contents/Frameworks`, copied
  with `ditto` so its symlinks stay, and the executable gets the rpath
  `@executable_path/../Frameworks` to find it there. Its XPC services are
  left out, as only a sandboxed app uses them, and so are its headers and
  module map, as Xcode leaves them out. Its license is in
  `THIRD_PARTY_NOTICES.txt`, which goes in `Contents/Resources` beside
  DevSweep's `LICENSE`.
- **Updates**: the app people download gets `SUFeedURL`, the appcast the
  release workflow attaches to each release, and `SUPublicEDKey`, the key
  its updates are signed with, both from `version.env`. A development build
  gets no feed, so it never offers to replace itself with a release;
  `FEED_URL=<url>` gives either build another one, such as a local appcast to
  try an update with. `SUEnableAutomaticChecks` is left out, so Sparkle asks
  on the second launch whether to check automatically, and
  `SUEnableSystemProfiling` is off.
- **The signature** is ad hoc with the hardened runtime, enough to run the app
  on this Mac. When `DEVELOPER_ID_APPLICATION` names a Developer ID Application
  identity in the keychain, the script signs with it and a secure timestamp
  instead; `Scripts/sign-and-notarize.sh` then notarizes and staples. Either
  way it signs inside out: Sparkle's `Autoupdate` and `Updater.app`, then its
  framework, then the app. The hardened runtime loads only frameworks signed
  by the app's own team, which an ad hoc signature has none of, so an ad hoc
  build is signed with `com.apple.security.cs.disable-library-validation`; a
  Developer ID build needs no entitlements. App Sandbox stays off: the app
  has to read and clean other tools' caches.

The bundle is put together in a temp folder and replaces the one in `build/`
only once it is signed, so a failed build or signature leaves the previous
bundle as it was.

An ad hoc signed app is not notarized, so the first time it opens Gatekeeper
refuses it; open it from Finder with Control-click > Open, or allow it in
System Settings > Privacy & Security.

## The command line tool

```bash
swift build -c release --product devsweep    # .build/release/devsweep
Scripts/install-cli.sh                       # link it into ~/.local/bin
Scripts/install-cli.sh --uninstall           # put back what was there
```

## Renaming

The product's names live in `version.env` and `Sources/DevSweepKit/Support/ProductInfo.swift`.
A new name is a change to those two files, the folder names that carry it
(`Sources/DevSweepApp`, the test targets), and the Homebrew files in `packaging/`.
