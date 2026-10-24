#!/usr/bin/env bash
#
# Packages the app from the DevSweepApp executable: an Info.plist with the
# bundle id and version from version.env, the icon from docs/icon, and
# a signature. Prints the bundle's path.
#
# Usage: Scripts/package_app.sh [release|debug]   default release
#
# A debug build goes to build/debug/DevSweep.app with its own bundle id, the
# release one's plus .debug, so a debug run never replaces the bundle you
# open, nor shares its settings.
#
# Signing: ad hoc, unless DEVELOPER_ID_APPLICATION names a Developer ID
# Application identity in the keychain; then hardened runtime and a secure
# timestamp, ready for Scripts/sign-and-notarize.sh. App Sandbox stays off.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${1:-${CONFIG:-release}}"
# shellcheck source=../version.env
source "$root/version.env"
destination="$root/build/$PRODUCT_NAME.app"
bundle_id="$BUNDLE_ID"
if [[ "$config" == debug ]]; then
  destination="$root/build/debug/$PRODUCT_NAME.app"
  bundle_id="$BUNDLE_ID.debug"
fi

swift build --package-path "$root" -c "$config" --product DevSweepApp >&2
bin="$(swift build --package-path "$root" -c "$config" --product DevSweepApp --show-bin-path)"

# The bundle is put together in a temp folder and replaces the one in build/
# only once it is signed, so a failed step leaves the previous bundle whole.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
app="$work/$PRODUCT_NAME.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/DevSweepApp" "$app/Contents/MacOS/$PRODUCT_NAME"

# The icon: docs/icon/AppIcon.icns, drawn by Scripts/make_icon.sh, or real
# artwork in its place.
cp "$root/docs/icon/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"

# Which build this is, so a bundle can say what it was built from: the
# commit, whether the tree had uncommitted changes, and whether it is signed
# for release. The app shows the commit in About, and in the overview's
# status line unless it is signed for release.
commit="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
dirty="<false/>"
[[ -z "$(git -C "$root" status --porcelain 2>/dev/null)" ]] || dirty="<true/>"
identity="${DEVELOPER_ID_APPLICATION:-}"
release_signed="<false/>"
[[ -z "$identity" ]] || release_signed="<true/>"

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$PRODUCT_NAME</string>
  <key>CFBundleDisplayName</key><string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleExecutable</key><string>$PRODUCT_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
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
</dict>
</plist>
EOF

if [[ -n "$identity" ]]; then
  codesign --force --sign "$identity" --options runtime --timestamp "$app" >&2
else
  codesign --force --sign - --options runtime "$app" >&2
fi

mkdir -p "$(dirname "$destination")"
rm -rf "$destination"
mv "$app" "$destination"
echo "$destination"
