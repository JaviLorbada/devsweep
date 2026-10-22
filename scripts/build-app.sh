#!/usr/bin/env bash
#
# Builds DevClean.app from the DevCleanApp executable target.
#
# Usage: scripts/build-app.sh            release build into build/DevClean.app
#        CONFIG=debug scripts/build-app.sh
#
# The bundle is signed ad hoc so macOS runs it locally. Developer ID signing
# and notarization are release work and not done here.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${CONFIG:-release}"
app="$root/build/DevClean.app"

swift build --package-path "$root" -c "$config" --product DevCleanApp >&2
bin="$(swift build --package-path "$root" -c "$config" --product DevCleanApp --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/DevCleanApp" "$app/Contents/MacOS/DevClean"

cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DevClean</string>
  <key>CFBundleDisplayName</key><string>DevClean</string>
  <key>CFBundleIdentifier</key><string>com.javilorbada.devclean</string>
  <key>CFBundleExecutable</key><string>DevClean</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

# Ad hoc signature with the hardened runtime, App Sandbox off (HANDOFF section 3).
codesign --force --sign - --options runtime "$app" >&2
echo "$app"
