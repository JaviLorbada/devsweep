#!/usr/bin/env bash
#
# Writes the appcast for an app zip: Sparkle's feed with one update, the
# zip, signed with the EdDSA private key, and the version's notes from
# CHANGELOG.md for Sparkle's update window. It goes beside the zip as
# appcast.xml, and is checked against version.env's UPDATE_PUBLIC_KEY, the
# key the app trusts, so a release can't publish an update every copy
# would refuse.
#
# Usage: Scripts/appcast.sh <app zip> <download URL prefix>
#   The prefix is where the zip is downloaded from: the release's download
#   folder in the release workflow, a local server in Scripts/try_update.sh.
#   The private key is SPARKLE_PRIVATE_KEY, as `generate_keys -x` exports it,
#   in the release workflow; without it, the login keychain's, under the
#   account devsweep, where generate_keys keeps it. macOS may ask to allow
#   generate_appcast to read it. PUBLIC_KEY checks against another key, as
#   Scripts/try_update.sh does with a throwaway pair.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
zip="${1:-}"
prefix="${2:-}"
if [[ ! -f "$zip" || -z "$prefix" ]]; then
  sed -n '10p' "${BASH_SOURCE[0]}" | sed 's/^# //' >&2
  exit 2
fi
# shellcheck source=../version.env
source "$root/version.env"

# Sparkle's tools come with the package SwiftPM resolved for the app.
swift package --package-path "$root" resolve >&2
tools="$root/.build/artifacts/sparkle/Sparkle/bin"

# generate_appcast reads a folder: the zip, and its notes beside it under the
# same name, as Markdown, which it embeds in the update.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
name="$(basename "$zip" .zip)"
cp "$zip" "$work/"
"$root/Scripts/release_notes.sh" "$MARKETING_VERSION" --changes > "$work/$name.md"
options=(--download-url-prefix "${prefix%/}/" --embed-release-notes
  --link "https://github.com/${GITHUB_REPOSITORY:-JaviLorbada/devsweep}" -o "$work/appcast.xml")
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$tools/generate_appcast" --ed-key-file - "${options[@]}" "$work" >&2
else
  "$tools/generate_appcast" --account devsweep "${options[@]}" "$work" >&2
fi

appcast="$(dirname "$zip")/appcast.xml"
cp "$work/appcast.xml" "$appcast"
swift "$root/Scripts/check_appcast.swift" "$appcast" "$zip" "${PUBLIC_KEY:-$UPDATE_PUBLIC_KEY}" >&2
echo "$appcast"
