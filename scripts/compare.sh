#!/usr/bin/env bash
#
# Runs the bash script and the Swift binary against the same fake home folder,
# with the same stubs for xcrun, brew, pgrep, defaults and xcode-select, and
# diffs what they print. Nothing outside the temp folder is read or written,
# apart from git and the system tools the bash script itself runs.
#
# Usage: scripts/compare.sh [path to dotfiles checkout]
#   KEEP=1 keeps the temp folder and prints where it is.
#   RUN=1 also compares --run --yes, each against its own copy of the fake home.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dotfiles="${1:-${DOTFILES:-$HOME/Documents/Workspace/dotfiles}}"
script="$dotfiles/bin/devclean"
[[ -x "$script" ]] || { echo "compare.sh: $script not found" >&2; exit 1; }

swift build --package-path "$root" --product devclean >&2
binary="$(swift build --package-path "$root" --product devclean --show-bin-path)/devclean"

work="$(mktemp -d)"
if [[ -n "${KEEP:-}" ]]; then
  echo "Keeping $work" >&2
else
  trap 'rm -rf "$work"' EXIT
fi

fill() { mkdir -p "$1"; echo "data" > "$1/file"; }
plist() { printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>%s</dict></plist>\n' "$2" > "$1"; }

# make_home <folder> [big]: with "big", the SwiftPM cache holds 1.4 GB so the
# report shows GB. The --run copies leave it out: APFS can give two identical
# freshly written files different block counts, so two copies of a big file
# don't measure the same, whoever measures them.
make_home() {
  local home="$1" ws="$1/Workspace" dd="$1/Library/Developer/Xcode/DerivedData" n
  mkdir -p "$ws"

  # DerivedData: shared caches, seven projects, one gone, one other folder
  fill "$dd/CompilationCache.noindex"
  dd if=/dev/zero of="$dd/CompilationCache.noindex/blob" bs=1024 count=3000 2>/dev/null
  fill "$dd/ModuleCache.noindex"
  fill "$dd/SymbolCache.noindex"
  for n in 1 2 3 4 5 6 7; do
    mkdir -p "$ws/P$n/P$n.xcodeproj"
    fill "$dd/P$n-abcdefghijklmnopqrstuvwxyz"
    plist "$dd/P$n-abcdefghijklmnopqrstuvwxyz/info.plist" \
      "<key>LastAccessedDate</key><date>2026-09-0${n}T10:00:00Z</date><key>WorkspacePath</key><string>$ws/P$n/P$n.xcodeproj</string>"
  done
  dd if=/dev/zero of="$dd/P7-abcdefghijklmnopqrstuvwxyz/big" bs=1024 count=2048 2>/dev/null
  fill "$dd/Gone-abcdefghijklmnopqrstuvwxyz"
  plist "$dd/Gone-abcdefghijklmnopqrstuvwxyz/info.plist" \
    "<key>LastAccessedDate</key><date>2026-03-02T10:00:00Z</date><key>WorkspacePath</key><string>$ws/Gone/Gone.xcworkspace</string>"
  mkdir -p "$ws/AVeryLongProjectFolderName/AnEvenLongerProjectName.xcodeproj"
  fill "$dd/Long-abcdefghijklmnopqrstuvwxyz"
  plist "$dd/Long-abcdefghijklmnopqrstuvwxyz/info.plist" \
    "<key>WorkspacePath</key><string>$ws/AVeryLongProjectFolderName/AnEvenLongerProjectName.xcodeproj</string>"

  # Simulators, device caches, Device Support
  fill "$home/Library/Developer/CoreSimulator/Devices/F3062B90-F7DB-4DBF-A21D-9AF6BC6EC06D"
  fill "$home/Library/Containers/com.apple.CoreDevice.CoreDeviceService/Data/Library/Caches/AppInstallationBinaryDeltas"
  local ds="$home/Library/Developer/Xcode/iOS DeviceSupport"
  fill "$ds/iPhone15,2 27.0 (24A435)"; fill "$ds/iPhone15,2 26.6.1 (23G80)"
  fill "$ds/16.4 (20E247) arm64e"; fill "$ds/16.4 (20E247)"; fill "$ds/15.5 (19F77)"; fill "$ds/Some Folder"
  fill "$home/Library/Developer/Xcode/macOS DeviceSupport/15.0"
  fill "$home/Library/Developer/Xcode/macOS DeviceSupport/14.5"

  # Caches
  fill "$home/Library/Caches/org.swift.swiftpm/repositories"
  if [[ "${2:-}" == big ]]; then
    dd if=/dev/zero of="$home/Library/Caches/org.swift.swiftpm/repositories/pack" bs=1024 count=1500000 2>/dev/null
  fi
  fill "$home/.npm/_cacache"; fill "$home/.npm/_npx"
  fill "$home/Library/Caches/CocoaPods"; fill "$home/Library/Caches/JetBrains/Toolbox/download"

  # Build folders
  touch "$ws/P1/Package.swift"; fill "$ws/P1/.build"
  mkdir -p "$ws/My App"; touch "$ws/My App/Package.swift"; fill "$ws/My App/.build"
  fill "$ws/P2/build/App.build"; mkdir -p "$ws/P2/build/XCBuildData"
  mkdir -p "$ws/android/app"; touch "$ws/android/app/build.gradle.kts"; fill "$ws/android/app/build"
  mkdir -p "$ws/Broken"; touch "$ws/Broken/Package.swift"; fill "$ws/Broken/.build"
  git -C "$ws/Broken" init -q; git -C "$ws/Broken" add -f .build/file; echo corrupt > "$ws/Broken/.git/index"
  mkdir -p "$ws/Tracked"; touch "$ws/Tracked/Package.swift"; fill "$ws/Tracked/.build"
  git -C "$ws/Tracked" init -q; git -C "$ws/Tracked" add -f .build/file

  # Xcodes
  local app
  for app in "Xcode.app 27.0 27A266a" "Xcode-27.1.app 27.1 27A9269"; do
    set -- $app
    mkdir -p "$home/Applications/$1/Contents"
    plist "$home/Applications/$1/Contents/Info.plist" "<key>CFBundleShortVersionString</key><string>$2</string>"
    plist "$home/Applications/$1/Contents/version.plist" "<key>ProductBuildVersion</key><string>$3</string>"
  done
}

make_stubs() {
  local stubs="$1"
  mkdir -p "$stubs"
  cat > "$work/runtimes.json" <<EOF
{
  "RECENT-RUNTIME": { "build": "24A434", "version": "27.0", "sizeBytes": 8589934592,
    "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0", "lastUsedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" },
  "OLD-RUNTIME": { "build": "21F79", "version": "17.5", "sizeBytes": 7516192768,
    "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-17-5", "lastUsedAt": "2020-01-01T00:00:00Z" },
  "NEVER-RUNTIME": { "build": "22A3351", "version": "18.0", "sizeBytes": 1000000,
    "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.watchOS-18-0" },
  "TV-RUNTIME": { "build": "23J1", "version": "26.1", "sizeBytes": 3000000000,
    "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.tvOS-26-1", "lastUsedAt": "2026-10-01T00:00:00Z" }
}
EOF
  cat > "$work/devices.json" <<'EOF'
{ "devices": {
  "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [ { "name": "iPhone" }, { "name": "iPad" } ],
  "com.apple.CoreSimulator.SimRuntime.tvOS-26-1": [ { "name": "Apple TV" } ] } }
EOF
  { echo '#!/bin/bash'; cat <<'EOF'
echo "xcrun $*" >> "$STUB_LOG"
case "$*" in
  "simctl list devices unavailable")
    echo "-- Unavailable: com.apple.CoreSimulator.SimRuntime.iOS-26-2 --"
    echo "    iPad Pro (M5) (F3062B90-F7DB-4DBF-A21D-9AF6BC6EC06D) (Shutdown) (unavailable, runtime profile not found)"
    ;;
  "simctl runtime list -j") cat "$WORK/runtimes.json" ;;
  "simctl list devices -j") cat "$WORK/devices.json" ;;
esac
EOF
  } > "$stubs/xcrun"
  { echo '#!/bin/bash'; cat <<'EOF'
echo "brew $*" >> "$STUB_LOG"
case "$*" in
  *--dry-run*) echo "==> This operation would free approximately 1.5GB of disk space." ;;
esac
EOF
  } > "$stubs/brew"
  printf '#!/bin/bash\nexit 1\n' > "$stubs/pgrep"
  printf '#!/bin/bash\nexit 1\n' > "$stubs/defaults"
  printf '#!/bin/bash\necho "$HOME/Applications/Xcode.app/Contents/Developer"\n' > "$stubs/xcode-select"
  chmod +x "$stubs"/*
}

# run_one <label> <program> <home> [args...]: stdout to <label>.out, stderr to <label>.err
run_one() {
  local label="$1" program="$2" home="$3"
  shift 3
  (
    cd "$work"
    export HOME="$home" WORK="$work" STUB_LOG="$work/$label.log"
    export DEVCLEAN_PROJECT_DIRS="$home/Workspace:$home/Missing" DEVCLEAN_APPLICATIONS_DIRS="$home/Applications"
    export PATH="$work/stubs:$PATH"
    set +e
    "$program" "$@" > "$work/$label.out" 2> "$work/$label.err"
    echo "$?" > "$work/$label.status"
  )
}

compare() {
  local name="$1" status=0 part
  for part in out err status log; do
    if ! diff -u "$work/bash-$name.$part" "$work/swift-$name.$part" > "$work/$name.$part.diff"; then
      echo "DIFFERENT: $name $part" >&2
      cat "$work/$name.$part.diff" >&2
      status=1
    fi
  done
  [[ "$status" -eq 0 ]] && echo "identical: $name (stdout, stderr, exit status, tool calls)" >&2
  return "$status"
}

make_stubs "$work/stubs"
make_home "$work/home" big
failed=0

run_one bash-report "$script" "$work/home"
run_one swift-report "$binary" "$work/home"
cp "$work/bash-report.out" "$work/report.txt"
# Free space moves between the two runs on a live machine; show both, compare the rest.
echo "free space seen: bash '$(grep '^  Free space now' "$work/bash-report.out" | tr -s ' ')'," \
  "swift '$(grep '^  Free space now' "$work/swift-report.out" | tr -s ' ')'" >&2
sed -i '' -E 's/^(  Free space now +).*/\1(varies)/' "$work/bash-report.out" "$work/swift-report.out"
compare report || failed=1

if [[ -n "${RUN:-}" ]]; then
  # Built from scratch rather than copied: cp makes sparse copies, which du
  # measures smaller.
  rm -rf "$work/home"
  make_home "$work/home-bash"
  make_home "$work/home-swift"
  run_one bash-run "$script" "$work/home-bash" --run --yes
  run_one swift-run "$binary" "$work/home-swift" --run --yes
  # The folders differ by name; compare what each printed with the name removed.
  for part in out err; do
    sed -i '' -e "s#home-bash#home-X#g" -e "s#home-swift#home-X#g" "$work/bash-run.$part" "$work/swift-run.$part"
  done
  # Free space depends on what else is on the disk at each moment, including
  # the other copy of the fake home.
  sed -i '' -E -e 's/^Done\. Free space: .*/Done. Free space: (varies)/' \
    -e 's/^(  Free space now +).*/\1(varies)/' "$work/bash-run.out" "$work/swift-run.out"
  compare run || failed=1
  (cd "$work/home-bash" && find . | sort) > "$work/bash-tree"
  (cd "$work/home-swift" && find . | sort) > "$work/swift-tree"
  if diff -u "$work/bash-tree" "$work/swift-tree" >&2; then
    echo "identical: folders left after --run ($(wc -l < "$work/bash-tree" | tr -d ' ') entries)" >&2
  else
    echo "DIFFERENT: folders left after --run" >&2
    failed=1
  fi
fi

echo >&2
echo "Report from the bash script:" >&2
cat "$work/report.txt"
exit "$failed"
