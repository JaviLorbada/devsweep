#!/usr/bin/env bash
#
# Prints a release's notes: its section of CHANGELOG.md (or Unreleased when it
# has none yet), and how the build is signed, from dist/signing.txt.
#
# Usage: Scripts/release_notes.sh <version>

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:?usage: Scripts/release_notes.sh <version>}"
# shellcheck source=../version.env
source "$root/version.env"

section() {
  awk -v heading="## $1" '
    $0 == heading { found = 1; next }
    found && /^## / { exit }
    found { print }
  ' "$root/CHANGELOG.md"
}

notes="$(section "$version")"
[[ -n "${notes//[[:space:]]/}" ]] || notes="$(section Unreleased)"
printf '%s\n' "$notes" | sed -e '/./,$!d'

if [[ "$(cat "$root/dist/signing.txt" 2>/dev/null)" == "notarized" ]]; then
  printf '\nSigned with Developer ID and notarized by Apple.\n'
else
  printf '\n**Not notarized.** This build is signed ad hoc. The first time you open %s, Control-click it in Finder and choose Open, or allow it in System Settings > Privacy & Security. The command line tool may need `xattr -d com.apple.quarantine %s` after downloading.\n' "$PRODUCT_NAME" "$CLI_NAME"
fi
