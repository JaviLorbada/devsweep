# Packaging

The repository is SwiftPM only; there is no Xcode project. To work in Xcode,
open `Package.swift`: Xcode keeps its workspace in
`.swiftpm/xcode/package.xcworkspace`, which stays out of git.

## The app

```bash
Scripts/package_app.sh          # release build into build/DevSweep Dev.app
Scripts/package_app.sh debug    # debug build, with the debug-only harnesses
```

Both are development builds: DevSweep Dev, with a DEV band on the icon
(`docs/icon/development/AppIcon.icns`), the bundle id
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
- **The icon** is `docs/icon/AppIcon.icns`. `Scripts/make_icon.sh` draws it
  from `AppIconView` in `Sources/DevSweepApp/Views/Style/AppIcon.swift`, a ring in the five
  family colors on a dark rounded square: it writes the PNGs an iconset holds,
  `icon_16x16.png` up to `icon_512x512@2x.png`, to `docs/icon` and builds the
  `.icns` from them with `iconutil`. It is a placeholder; real artwork goes in
  the same files, and the packaging takes it as it is.
- **The signature** is ad hoc with the hardened runtime, enough to run the app
  on this Mac. When `DEVELOPER_ID_APPLICATION` names a Developer ID Application
  identity in the keychain, the script signs with it and a secure timestamp
  instead; `Scripts/sign-and-notarize.sh` then notarizes and staples. App
  Sandbox stays off: the app has to read and clean other tools' caches.

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
