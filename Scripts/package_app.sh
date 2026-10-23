#!/usr/bin/env bash
#
# Packages the app from the DevSweepApp executable: an Info.plist with the
# bundle id and version from version.env, the icon built from docs/icon, and
# a signature. Prints the bundle's path.
#
# Usage: Scripts/package_app.sh [release|debug]   default release
#
# Signing: ad hoc, unless DEVELOPER_ID_APPLICATION names a Developer ID
# Application identity in the keychain; then hardened runtime and a secure
# timestamp, ready for Scripts/sign-and-notarize.sh. App Sandbox stays off.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${1:-${CONFIG:-release}}"
# shellcheck source=../version.env
source "$root/version.env"
app="$root/build/$PRODUCT_NAME.app"

swift build --package-path "$root" -c "$config" --product DevSweepApp >&2
bin="$(swift build --package-path "$root" -c "$config" --product DevSweepApp --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/DevSweepApp" "$app/Contents/MacOS/$PRODUCT_NAME"

# The icon: docs/icon holds the PNGs an iconset needs, icon_16x16.png up to
# icon_512x512@2x.png; iconutil turns them into one .icns.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/AppIcon.iconset"
cp "$root"/docs/icon/icon_*.png "$work/AppIcon.iconset/"
iconutil -c icns "$work/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$PRODUCT_NAME</string>
  <key>CFBundleDisplayName</key><string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$PRODUCT_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

identity="${DEVELOPER_ID_APPLICATION:-}"
if [[ -n "$identity" ]]; then
  codesign --force --sign "$identity" --options runtime --timestamp "$app" >&2
else
  codesign --force --sign - --options runtime "$app" >&2
fi
echo "$app"
