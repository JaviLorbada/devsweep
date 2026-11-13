#!/usr/bin/env bash
#
# Prints a release's notes for GitHub: the README's screenshot, its section
# of CHANGELOG.md (or Unreleased when it has none yet), what to download,
# how the build is signed (from dist/signing.txt), and the zips' SHA-256 when
# they are in dist/. GitHub shows every newline in release notes, so the
# lines a paragraph or a list item wraps onto are joined.
#
# Usage: Scripts/release_notes.sh <version>

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:?usage: Scripts/release_notes.sh <version>}"
# shellcheck source=../version.env
source "$root/version.env"
repository="${GITHUB_REPOSITORY:-JaviLorbada/devsweep}"
app_zip="$PRODUCT_NAME-$version.zip"
cli_zip="$CLI_NAME-$version-macos.zip"
download="https://github.com/$repository/releases/download/v$version"
files="https://raw.githubusercontent.com/$repository/v$version"

section() {
  awk -v heading="## $1" '
    $0 == heading { found = 1; next }
    found && /^## / { exit }
    found { print }
  ' "$root/CHANGELOG.md"
}

unwrap() {
  awk '
    function flush() { if (line != "") print line; line = "" }
    /^$/ { flush(); print ""; next }
    /^#/ || /^\|/ { flush(); print; next }
    /^(- |\* |[0-9]+\. )/ { flush(); line = $0; next }
    /^ +/ && line != "" { sub(/^ +/, ""); line = line " " $0; next }
    { line = (line == "" ? $0 : line " " $0) }
    END { flush() }
  '
}

notes="$(section "$version")"
[[ -n "${notes//[[:space:]]/}" ]] || notes="$(section Unreleased)"

# The window, light or dark as the reader's GitHub is, from the tagged files.
cat <<EOF
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="$files/docs/screenshot-dark.png">
  <img alt="The $PRODUCT_NAME window: a ring of what each cache holds, the items to clean, and the inspector for DerivedData" src="$files/docs/screenshot-light.png">
</picture>

EOF
# Links relative to the repository, like docs/architecture.md, point at the
# tagged version's files; on a release page they would point nowhere.
printf '%s\n' "$notes" | sed -e '/./,$!d' | unwrap | cat -s \
  | sed -E "s#\\]\\(([^):#]+)\\)#](https://github.com/$repository/blob/v$version/\\1)#g"

cat <<EOF

### Download

| File | What it is |
|---|---|
| [$app_zip]($download/$app_zip) | The app. Unzip it and move $PRODUCT_NAME to Applications. |
| [$cli_zip]($download/$cli_zip) | The command line tool, \`$CLI_NAME\`, with its licenses. |

Needs macOS 26 on a Mac with Apple silicon.
EOF

if [[ "$(cat "$root/dist/signing.txt" 2>/dev/null)" == "notarized" ]]; then
  printf '\nBoth are signed with Developer ID and notarized by Apple, so they open like any app downloaded from the internet.\n'
else
  printf '\n**Not notarized.** This build is signed ad hoc. The first time you open %s, Control-click it in Finder and choose Open, or allow it in System Settings > Privacy & Security. The command line tool may need `xattr -d com.apple.quarantine %s` after downloading.\n' "$PRODUCT_NAME" "$CLI_NAME"
fi

if [[ -f "$root/dist/$app_zip" && -f "$root/dist/$cli_zip" ]]; then
  printf '\nSHA-256:\n\n```\n'
  (cd "$root/dist" && shasum -a 256 "$app_zip" "$cli_zip")
  printf '```\n'
fi
