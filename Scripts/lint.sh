#!/usr/bin/env bash
#
# Lints or formats the Swift sources with the repository's .swiftformat and
# .swiftlint.yml. Lint is strict: every warning fails.
#
# Usage: Scripts/lint.sh lint     swiftformat --lint, then swiftlint --strict
#        Scripts/lint.sh format   rewrite Sources and Tests with swiftformat

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "lint.sh: $1 is not installed; brew install $1" >&2; exit 1; }
}

case "${1:-lint}" in
  lint)
    need swiftformat
    need swiftlint
    swiftformat Sources Tests --lint
    swiftlint --strict --no-cache
    ;;
  format)
    need swiftformat
    swiftformat Sources Tests
    ;;
  *)
    sed -n '3,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
