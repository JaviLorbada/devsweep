#!/usr/bin/env bash
#
# Opens build/DevSweep.app, the bundle `make app` makes. A DevSweep already
# running is asked to quit first, and the new one opens only once it has
# exited, since `open` would otherwise bring the running copy forward.
# Asking it to quit is an Apple event, which macOS lets the terminal send
# only with its Automation permission for DevSweep; without that, this says
# so and opens nothing.
#
# Usage: make app && Scripts/open_app.sh

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../version.env
source "$root/version.env"
app="$root/build/$PRODUCT_NAME.app"

[[ -d "$app" ]] || { echo "open_app.sh: there is no $app; run make app first" >&2; exit 1; }

# The pid of a running DevSweep, whichever copy it is, or nothing.
running() { lsappinfo info -only pid "$BUNDLE_ID" | sed -n 's/^"pid"=//p'; }

pid="$(running)"
if [[ -n "$pid" ]]; then
  if ! error="$(osascript -e 'with timeout of 10 seconds' -e "tell application id \"$BUNDLE_ID\" to quit" \
    -e 'end timeout' 2>&1)"; then
    case "$error" in
      *-1743* | *-1744*)
        echo "Not opened: macOS refused to let this terminal quit the running $PRODUCT_NAME (pid $pid)," \
          "as it has no Automation permission for it. Allow it in System Settings > Privacy & Security >" \
          "Automation, or quit $PRODUCT_NAME yourself, then run this again." >&2
        ;;
      *-128*) echo "Not opened: the running $PRODUCT_NAME (pid $pid) declined to quit." >&2 ;;
      *) echo "Not opened: asking the running $PRODUCT_NAME (pid $pid) to quit failed: $error" >&2 ;;
    esac
    exit 1
  fi
  # The quit event is answered before the app has exited.
  for _ in {1..50}; do
    [[ -z "$(running)" ]] && break
    sleep 0.2
  done
  if [[ -n "$(running)" ]]; then
    echo "Not opened: $PRODUCT_NAME (pid $(running)) is still running 10 seconds after it was asked to quit." >&2
    exit 1
  fi
fi

commit="$(defaults read "$app/Contents/Info" DevSweepCommit 2>/dev/null || echo "an unknown commit")"
echo "Opening $app, built from $commit."
open "$app"
