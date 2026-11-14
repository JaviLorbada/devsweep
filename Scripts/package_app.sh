#!/usr/bin/env bash
#
# Packages the app from the DevSweepApp executable: an Info.plist with the
# bundle id and version from version.env, the icon compiled from its Icon
# Composer file in docs/icon, Sparkle's framework, and a signature. Prints
# the bundle's path.
#
# Usage: Scripts/package_app.sh [release|debug]   default release
#
# What it packages is a development build, "DevSweep Dev" with its own icon
# (docs/icon/development), its own bundle id (the released one's plus .dev,
# or .debug for a debug build) and so its own settings and last scan: it can
# run beside the released app and be told apart. FOR_RELEASE=1, as
# Scripts/build_release.sh sets it, packages the app people download:
# DevSweep, its bundle id and icon.
# A release build goes to build/, a debug one to build/debug/.
#
# Updates: the app people download looks for them at version.env's
# UPDATE_FEED_URL. A development build has no feed, so it never offers to
# replace itself with a release. FEED_URL names another feed for either,
# such as a local appcast to try an update with.
#
# Signing: ad hoc, unless DEVELOPER_ID_APPLICATION names a Developer ID
# Application identity in the keychain; then hardened runtime and a secure
# timestamp, ready for Scripts/sign-and-notarize.sh. Sparkle's helpers and
# framework are signed first, then the app around them. App Sandbox stays off.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${1:-${CONFIG:-release}}"
# shellcheck source=../version.env
source "$root/version.env"
if [[ -n "${FOR_RELEASE:-}" && "$config" != debug ]]; then
  name="$PRODUCT_NAME"
  bundle_id="$BUNDLE_ID"
  icon="$root/docs/icon/AppIcon.icon"
  development="<false/>"
  feed="${FEED_URL:-$UPDATE_FEED_URL}"
else
  name="$PRODUCT_NAME Dev"
  bundle_id="$BUNDLE_ID.dev"
  icon="$root/docs/icon/development/AppIcon.icon"
  development="<true/>"
  feed="${FEED_URL:-}"
fi
destination="$root/build/$name.app"
if [[ "$config" == debug ]]; then
  destination="$root/build/debug/$name.app"
  bundle_id="$BUNDLE_ID.debug"
fi

swift build --package-path "$root" -c "$config" --product DevSweepApp >&2
bin="$(swift build --package-path "$root" -c "$config" --product DevSweepApp --show-bin-path)"

# The bundle is put together in a temp folder and replaces the one in build/
# only once it is signed, so a failed step leaves the previous bundle whole.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
app="$work/$name.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
executable="$app/Contents/MacOS/$PRODUCT_NAME"
cp "$bin/DevSweepApp" "$executable"

# Sparkle, which updates the app, goes in Contents/Frameworks, where the
# executable looks for it once it has that rpath; SwiftPM gives it only
# @loader_path, for running from the build folder. ditto keeps the
# framework's symlinks, which its signature covers. Left out: the XPC
# services, which only a sandboxed app uses, and the headers and module
# map, which only building against it does, as Xcode leaves them out.
sparkle="$app/Contents/Frameworks/Sparkle.framework"
ditto "$bin/Sparkle.framework" "$sparkle"
rm -rf "$sparkle/XPCServices" "$sparkle/Versions/B/XPCServices"
for part in Headers PrivateHeaders Modules; do
  rm -rf "${sparkle:?}/$part" "$sparkle/Versions/B/$part"
done
# The linker's signature goes first, as the rpath would break it; the
# executable is signed again with the app.
codesign --remove-signature "$executable"
install_name_tool -add_rpath @executable_path/../Frameworks "$executable"

# The icon, from docs/icon/AppIcon.icon or the development build's: its
# layers and appearances in Assets.car, and a flat AppIcon.icns.
"$root/Scripts/compile_icon.sh" "$icon" "$app/Contents/Resources"
# Its license travels with it, and so do those of the code it builds on.
cp "$root/LICENSE" "$root/THIRD_PARTY_NOTICES.txt" "$app/Contents/Resources/"

# Which build this is, so a bundle can say what it was built from: the
# commit, whether the tree had uncommitted changes, whether it is signed for
# release, and whether it is a development build. The app shows the commit in
# About, and in the overview's status line unless it is signed for release;
# a development build names itself DevSweep Dev and keeps its own last scan.
commit="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
dirty="<false/>"
[[ -z "$(git -C "$root" status --porcelain 2>/dev/null)" ]] || dirty="<true/>"
identity="${DEVELOPER_ID_APPLICATION:-}"
release_signed="<false/>"
[[ -z "$identity" ]] || release_signed="<true/>"

# Sparkle's settings. Without SUEnableAutomaticChecks, it asks on the second
# launch whether to check automatically, so nothing is turned on unasked; it
# never sends a profile of the Mac. Without a feed, the app starts no updater.
updates="  <key>SUPublicEDKey</key><string>$UPDATE_PUBLIC_KEY</string>
  <key>SUEnableSystemProfiling</key><false/>"
[[ -z "$feed" ]] || updates+="
  <key>SUFeedURL</key><string>$feed</string>"

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleDisplayName</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleExecutable</key><string>$PRODUCT_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>DevSweepCommit</key><string>$commit</string>
  <key>DevSweepTreeDirty</key>$dirty
  <key>DevSweepReleaseSigned</key>$release_signed
  <key>DevSweepDevelopment</key>$development
$updates
</dict>
</plist>
EOF

# Inside out, as nested code has to be: Sparkle's helpers, its framework,
# then the app. Each gets the hardened runtime, and none keeps the
# entitlements Sparkle's own ad hoc signature gave them.
sign() {
  if [[ -n "$identity" ]]; then
    codesign --force --sign "$identity" --options runtime --timestamp "$@" >&2
  else
    codesign --force --sign - --options runtime "$@" >&2
  fi
}
sign "$sparkle/Versions/B/Autoupdate"
sign "$sparkle/Versions/B/Updater.app"
sign "$sparkle"
if [[ -n "$identity" ]]; then
  sign "$app"
else
  # The hardened runtime loads only frameworks signed by the app's own team,
  # and an ad hoc signature has none, so an ad hoc build would refuse
  # Sparkle; it turns that check off, as Sparkle's docs suggest for
  # development. Signed with a Developer ID, one team signs both and the
  # check stays.
  cat > "$work/adhoc.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict>
</plist>
EOF
  sign --entitlements "$work/adhoc.entitlements" "$app"
fi
codesign --verify --deep --strict "$app" >&2

mkdir -p "$(dirname "$destination")"
rm -rf "$destination"
mv "$app" "$destination"
echo "$destination"
