#!/usr/bin/env bash
#
# Draws the app icon from AppIconView (Sources/DevSweepApp/AppIcon.swift) into
# docs/icon: the PNGs an iconset holds, icon_16x16.png up to
# icon_512x512@2x.png, and AppIcon.icns built from them with iconutil, which
# Scripts/package_app.sh puts in the bundle. For real artwork, put its PNGs
# and .icns there instead and leave this script be.
#
# Usage: Scripts/make_icon.sh

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
swift build --package-path "$root" --product DevSweepApp >&2
bin="$(swift build --package-path "$root" --product DevSweepApp --show-bin-path)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
iconset="$work/AppIcon.iconset"
mkdir "$iconset"
# A debug build draws the icon and quits when DEVSWEEP_ICON names a folder.
DEVSWEEP_ICON="$iconset" "$bin/DevSweepApp"
iconutil -c icns "$iconset" -o "$work/AppIcon.icns"

cp "$iconset"/icon_*.png "$root/docs/icon/"
cp "$work/AppIcon.icns" "$root/docs/icon/AppIcon.icns"
echo "$root/docs/icon/AppIcon.icns"
