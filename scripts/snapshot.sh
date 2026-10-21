#!/usr/bin/env bash
#
# Draws the app's window into PNG files without touching the real home folder:
# it builds a debug DevClean.app, makes a fake home in a temp folder with
# something in every item, puts stubs for xcrun, brew, pgrep, defaults and
# xcode-select first on PATH, and launches the app with that HOME. The app
# scans, draws its window into a file and quits. Nothing is cleaned.
#
# Usage: scripts/snapshot.sh [output folder] [screen...]
#   screens: overview scanning blocks runtimes xcodes remove-runtime cleaned putback,
#            any with -light (default: overview)
#   cleaned and putback clean what starts marked, in the fake home only, with
#   the Trash pointed at a folder inside it, and list what that folder holds.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-$root/build/snapshots}"
shift || true
screens=("${@:-overview}")
mkdir -p "$out"
out="$(cd "$out" && pwd)"

app="$(CONFIG=debug "$root/scripts/build-app.sh")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

blob() { mkdir -p "$(dirname "$1")"; dd if=/dev/zero of="$1" bs=1048576 count="$2" 2>/dev/null; }
plist() { mkdir -p "$(dirname "$1")"; printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>%s</dict></plist>\n' "$2" > "$1"; }

# make_home <folder>: a fake home with something in every item.
make_home() {
  local home="$1" ws="$1/Developer" dd project pkg app_dir ds
  dd="$home/Library/Developer/Xcode/DerivedData"
  blob "$dd/CompilationCache.noindex/cache" 46
  blob "$dd/ModuleCache.noindex/cache" 9
  for project in "Atlas 25 2026-10-19" "Fieldwork 9 2026-09-02" "Recipes 4 2026-03-11" "Pebble 2 2026-08-21" "Ledger 2 2026-07-14" "Notes 1 2026-05-02"; do
    set -- $project
    mkdir -p "$ws/$1/$1.xcodeproj"
    blob "$dd/$1-abcdefghijklmnop/Build/blob" "$2"
    plist "$dd/$1-abcdefghijklmnop/info.plist" \
      "<key>LastAccessedDate</key><date>${3}T10:00:00Z</date><key>WorkspacePath</key><string>$ws/$1/$1.xcodeproj</string>"
  done
  blob "$dd/WeatherDemo-abcdefghijklmnop/Build/blob" 6
  plist "$dd/WeatherDemo-abcdefghijklmnop/info.plist" \
    "<key>LastAccessedDate</key><date>2026-01-10T10:00:00Z</date><key>WorkspacePath</key><string>$ws/WeatherDemo/WeatherDemo.xcodeproj</string>"

  blob "$home/Library/Caches/org.swift.swiftpm/repositories/pack" 24
  ds="$home/Library/Developer/Xcode/iOS DeviceSupport"
  blob "$ds/iPhone17,1 27.0 (24A435)/Symbols/blob" 2
  blob "$ds/iPhone17,1 26.4 (23E244)/Symbols/blob" 9
  blob "$ds/iPhone15,2 26.6.1 (23G80)/Symbols/blob" 7
  blob "$ds/iPhone15,2 25.0 (22A100)/Symbols/blob" 3
  blob "$home/Library/Developer/CoreSimulator/Devices/F3062B90-F7DB-4DBF-A21D-9AF6BC6EC06D/data/blob" 8
  blob "$home/Library/Developer/CoreSimulator/Devices/0CD98AA9-475F-4336-BCD7-383B43BC4DBA/data/blob" 5
  for pkg in Core Networking Design Storage; do
    touch "$ws/Atlas/Packages/$pkg/Package.swift" 2>/dev/null || { mkdir -p "$ws/Atlas/Packages/$pkg"; touch "$ws/Atlas/Packages/$pkg/Package.swift"; }
    blob "$ws/Atlas/Packages/$pkg/.build/debug/blob" 3
  done
  blob "$ws/Fieldwork/build/Fieldwork.build/blob" 5
  mkdir -p "$ws/Fieldwork/build/XCBuildData"
  blob "$ws/Ledger/build/Ledger.build/blob" 2
  blob "$home/.npm/_cacache/content/blob" 11
  blob "$home/.npm/_npx/blob" 2
  blob "$home/Library/Containers/com.apple.CoreDevice.CoreDeviceService/Data/Library/Caches/AppInstallationBinaryDeltas/blob" 7
  blob "$home/Library/Caches/CocoaPods/blob" 5
  blob "$home/Library/Caches/ms-playwright/blob" 3
  blob "$home/Library/Caches/JetBrains/Toolbox/download/blob" 1
  mkdir -p "$ws/android/app"; touch "$ws/android/app/build.gradle.kts"
  blob "$ws/android/app/build/intermediates/blob" 4

  for app_dir in "Xcode.app 27.1 27B48" "Xcode-26.4.app 26.4 17E192"; do
    set -- $app_dir
    plist "$home/Applications/$1/Contents/Info.plist" "<key>CFBundleShortVersionString</key><string>$2</string>"
    plist "$home/Applications/$1/Contents/version.plist" "<key>ProductBuildVersion</key><string>$3</string>"
    blob "$home/Applications/$1/Contents/Developer/blob" 12
  done
}

stubs="$work/stubs"
mkdir -p "$stubs"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$work/runtimes.json" <<EOF
{
  "6A1B2C3D-0000-4000-8000-000000000001": { "build": "24B5055e", "version": "27.1", "sizeBytes": 9019431321,
    "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-1", "lastUsedAt": "$now" },
  "4C1F2B8E-0D3A-4F6B-9C21-7E5A1B2C3DA2": { "build": "22F77", "version": "18.5", "sizeBytes": 8160437862,
    "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-5", "lastUsedAt": "2026-05-30T09:00:00Z" },
  "9E8D7C6B-0000-4000-8000-000000000003": { "build": "23R61", "version": "26.1", "sizeBytes": 4187593113,
    "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.watchOS-26-1", "lastUsedAt": "2026-09-01T09:00:00Z" }
}
EOF
cat > "$work/devices.json" <<'EOF'
{ "devices": {
  "com.apple.CoreSimulator.SimRuntime.iOS-27-1": [ {}, {}, {}, {} ],
  "com.apple.CoreSimulator.SimRuntime.watchOS-26-1": [ {} ] } }
EOF
cat > "$stubs/xcrun" <<EOF
#!/bin/bash
case "\$*" in
  "simctl list devices unavailable")
    echo "-- Unavailable: com.apple.CoreSimulator.SimRuntime.iOS-26-2 --"
    echo "    iPad Pro (M5) (F3062B90-F7DB-4DBF-A21D-9AF6BC6EC06D) (Shutdown) (unavailable, runtime profile not found)"
    echo "    iPhone 17 (0CD98AA9-475F-4336-BCD7-383B43BC4DBA) (Shutdown) (unavailable, runtime profile not found)"
    ;;
  "simctl runtime list -j") cat "$work/runtimes.json" ;;
  "simctl list devices -j") cat "$work/devices.json" ;;
  *) exit 1 ;;
esac
EOF
cat > "$stubs/brew" <<'EOF'
#!/bin/bash
case "$*" in
  *--dry-run*) echo "==> This operation would free approximately 38.2MB of disk space." ;;
  *) exit 1 ;;
esac
EOF
printf '#!/bin/bash\nexit 1\n' > "$stubs/pgrep"
printf '#!/bin/bash\nexit 1\n' > "$stubs/defaults"
printf '#!/bin/bash\necho "$HOME/Applications/Xcode.app/Contents/Developer"\n' > "$stubs/xcode-select"
chmod +x "$stubs"/*

for screen in "${screens[@]}"; do
  appearance=dark
  name="$screen"
  case "$screen" in
    *-light) appearance=light; screen="${screen%-light}" ;;
  esac
  # Every screen gets its own fresh home: cleaning changes it.
  home="$work/home-$name"
  make_home "$home"
  select=""
  [[ "$screen" == runtimes || "$screen" == remove-runtime ]] && select="4C1F2B8E-0D3A-4F6B-9C21-7E5A1B2C3DA2"
  HOME="$home" PATH="$stubs:/usr/bin:/bin:/usr/sbin:/sbin" DEVCLEAN_TRASH_FOLDER="$work/trash-$name" \
    DEVCLEAN_APPLICATIONS_DIRS="$home/Applications" \
    DEVCLEAN_SNAPSHOT="$out/$name.png" DEVCLEAN_SNAPSHOT_SCREEN="$screen" \
    DEVCLEAN_SNAPSHOT_APPEARANCE="$appearance" DEVCLEAN_SNAPSHOT_SELECT="$select" \
    "$app/Contents/MacOS/DevClean" >/dev/null 2>&1 &
  pid=$!
  for _ in $(seq 1 120); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
  done
  kill "$pid" 2>/dev/null || true
  [[ -f "$out/$name.png" ]] && echo "$out/$name.png" || echo "snapshot.sh: no image for $name" >&2
  if [[ -d "$work/trash-$name" ]]; then
    echo "  in the fake Trash after $name: $(ls "$work/trash-$name" | tr '\n' ',' | sed 's/,$//')" >&2
  fi
done
