#!/usr/bin/env bash
#
# Runs the bash script's own acceptance suite, test/devclean.bats from the
# dotfiles repo, unchanged, against the Swift devclean binary.
#
# The suite runs "${DOTFILES_DIR}/bin/devclean", where DOTFILES_DIR is the
# parent of the folder holding test_helper.bash. So this builds the binary,
# lays out a throwaway folder with bin/devclean pointing at it next to
# byte-identical copies of the two test files, and runs bats there.
#
# Usage: Scripts/bats.sh [path to dotfiles checkout] [extra bats arguments]
#        DOTFILES=... Scripts/bats.sh

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dotfiles="${1:-${DOTFILES:-$HOME/Documents/Workspace/dotfiles}}"
shift || true

for file in test/devclean.bats test/test_helper.bash; do
  [[ -f "$dotfiles/$file" ]] || { echo "bats.sh: $dotfiles/$file not found" >&2; exit 1; }
done
command -v bats >/dev/null || { echo "bats.sh: bats is not installed (brew install bats-core)" >&2; exit 1; }

swift build --package-path "$root" --product devclean >&2
binary="$(swift build --package-path "$root" --product devclean --show-bin-path)/devclean"

harness="$(mktemp -d)"
trap 'rm -rf "$harness"' EXIT
mkdir -p "$harness/bin" "$harness/test"
ln -s "$binary" "$harness/bin/devclean"
cp "$dotfiles/test/devclean.bats" "$dotfiles/test/test_helper.bash" "$harness/test/"
cmp "$dotfiles/test/devclean.bats" "$harness/test/devclean.bats"
cmp "$dotfiles/test/test_helper.bash" "$harness/test/test_helper.bash"

bats "$@" "$harness/test/devclean.bats"
