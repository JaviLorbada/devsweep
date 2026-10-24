# Packaging

The repository is SwiftPM only; there is no Xcode project. To work in Xcode,
open `Package.swift`: Xcode keeps its workspace in
`.swiftpm/xcode/package.xcworkspace`, which stays out of git.

## The app

```bash
Scripts/package_app.sh          # release build into build/DevSweep.app
Scripts/package_app.sh debug    # debug build, with the debug-only harnesses
```

The script builds the `DevSweepApp` executable and wraps it in a bundle:

- **Info.plist** gets the bundle id, name and version from `version.env`:
  `PRODUCT_NAME`, `BUNDLE_ID`, `MARKETING_VERSION` and `BUILD_NUMBER`. Change
  them there, never in the plist. `ProductInfo.swift` holds the same names for
  the code, and a test fails when the two disagree.
- **The icon** is `docs/icon/AppIcon.icns`. `Scripts/make_icon.sh` draws it
  from `AppIconView` in `Sources/DevSweepApp/AppIcon.swift`, a ring in the five
  family colors on a dark rounded square: it writes the PNGs an iconset holds,
  `icon_16x16.png` up to `icon_512x512@2x.png`, to `docs/icon` and builds the
  `.icns` from them with `iconutil`. It is a placeholder; real artwork goes in
  the same files, and the packaging takes it as it is.
- **The signature** is ad hoc with the hardened runtime, enough to run the app
  on this Mac. When `DEVELOPER_ID_APPLICATION` names a Developer ID Application
  identity in the keychain, the script signs with it and a secure timestamp
  instead; `Scripts/sign-and-notarize.sh` then notarizes and staples. App
  Sandbox stays off: the app has to read and clean other tools' caches.

The bundle is put together in a temp folder and replaces `build/DevSweep.app`
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
