#!/usr/bin/env bash
#
# Compiles an Icon Composer icon, docs/icon/AppIcon.icon or the development
# build's docs/icon/development/AppIcon.icon, into what a bundle's Resources
# hold: Assets.car, where macOS 26 finds the layered icon with its light, dark,
# clear and tinted appearances, and AppIcon.icns, the flat icon for whatever
# reads only that. The Info.plist names both: CFBundleIconName and
# CFBundleIconFile, AppIcon. Needs Xcode's actool.
#
# Usage: Scripts/compile_icon.sh <AppIcon.icon> <Resources folder>

set -euo pipefail

usage="usage: Scripts/compile_icon.sh <AppIcon.icon> <Resources folder>"
icon="${1:?$usage}"
resources="${2:?$usage}"
# Absolute: actool reads a relative path against a stale working directory.
icon="$(cd "$(dirname "$icon")" && pwd)/$(basename "$icon")"
mkdir -p "$resources"
resources="$(cd "$resources" && pwd)"
name="$(basename "$icon" .icon)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
if ! xcrun actool "$icon" --compile "$work" --platform macosx --minimum-deployment-target 26.0 \
  --app-icon "$name" --output-partial-info-plist "$work/partial.plist" \
  --errors --warnings --output-format human-readable-text > "$work/actool.log" 2>&1 \
  || grep -q -i -E "error|warning" "$work/actool.log"; then
  echo "compile_icon.sh: actool couldn't compile $icon:" >&2
  grep -v "^/\* com.apple" "$work/actool.log" >&2
  exit 1
fi
cp "$work/Assets.car" "$work/$name.icns" "$resources/"
