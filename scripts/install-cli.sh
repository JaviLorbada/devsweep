#!/usr/bin/env bash
#
# Builds the release devclean and links it into ~/.local/bin as devclean, in
# place of whatever devclean was there, usually a link to the bash script.
# The link it replaces is remembered, and --uninstall puts it back. Only the
# link in the bin folder changes; the bash script itself is never touched.
#
# Usage: scripts/install-cli.sh             build and link
#        scripts/install-cli.sh --uninstall remove the link, restore the old one
#
# DEVCLEAN_BIN_DIR picks another folder than ~/.local/bin.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bin_dir="${DEVCLEAN_BIN_DIR:-$HOME/.local/bin}"
link="$bin_dir/devclean"
# The target of the link this replaced, one line.
replaced="$bin_dir/.devclean-replaced"

usage() {
  sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

ours() {
  [[ -L "$link" && "$(readlink "$link")" == "$root"/.build/* ]]
}

install() {
  swift build --package-path "$root" -c release --product devclean >&2
  local binary
  binary="$(swift build --package-path "$root" -c release --product devclean --show-bin-path)/devclean"
  [[ -x "$binary" ]] || { echo "install-cli.sh: no binary at $binary" >&2; exit 1; }

  mkdir -p "$bin_dir"
  if [[ -L "$link" ]] && ! ours; then
    readlink "$link" > "$replaced"
  elif [[ -e "$link" && ! -L "$link" ]]; then
    echo "install-cli.sh: $link is a file, not a link; move it away first." >&2
    exit 1
  fi
  ln -sfn "$binary" "$link"
  echo "Linked $link -> $binary"
  [[ -f "$replaced" ]] && echo "It replaces the link to $(cat "$replaced"); --uninstall puts that back."

  local found
  found="$(PATH="$PATH" command -v devclean || true)"
  if [[ "$found" != "$link" ]]; then
    echo "Note: devclean on your PATH is ${found:-not found}, not $link. Put $bin_dir first on PATH." >&2
  fi
}

uninstall() {
  if ours; then
    rm -f "$link"
    echo "Removed $link"
  elif [[ -e "$link" || -L "$link" ]]; then
    echo "install-cli.sh: $link isn't this build's link; leaving it." >&2
  fi
  if [[ -f "$replaced" ]]; then
    if [[ ! -e "$link" && ! -L "$link" ]]; then
      ln -s "$(cat "$replaced")" "$link"
      echo "Restored $link -> $(cat "$replaced")"
    fi
    rm -f "$replaced"
  fi
}

case "${1:-}" in
  "") install ;;
  --uninstall) uninstall ;;
  -h|--help) usage ;;
  *) echo "Unknown option: $1 (see --help)" >&2; exit 2 ;;
esac
