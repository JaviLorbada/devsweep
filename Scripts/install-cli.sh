#!/usr/bin/env bash
#
# Builds the release devsweep and links it into ~/.local/bin as devsweep. If
# something else was linked there, the link it replaces is remembered and
# --uninstall puts it back. Only the link in the bin folder changes; the
# original bash script, devclean, is never touched.
#
# Usage: Scripts/install-cli.sh             build and link
#        Scripts/install-cli.sh --uninstall remove the link, restore the old one
#
# DEVSWEEP_BIN_DIR picks another folder than ~/.local/bin.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bin_dir="${DEVSWEEP_BIN_DIR:-$HOME/.local/bin}"
link="$bin_dir/devsweep"
# The target of the link this replaced, one line.
replaced="$bin_dir/.devsweep-replaced"

usage() {
  sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

ours() {
  [[ -L "$link" && "$(readlink "$link")" == "$root"/.build/* ]]
}

install() {
  swift build --package-path "$root" -c release --product devsweep >&2
  local binary
  binary="$(swift build --package-path "$root" -c release --product devsweep --show-bin-path)/devsweep"
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
  found="$(PATH="$PATH" command -v devsweep || true)"
  if [[ "$found" != "$link" ]]; then
    echo "Note: devsweep on your PATH is ${found:-not found}, not $link. Put $bin_dir first on PATH." >&2
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
