#!/usr/bin/env bash
#
# Tries an update end to end before a release, on this Mac and nowhere
# else: an older DevSweep Dev updates itself to this checkout's from a local
# appcast, through Sparkle, as an installed DevSweep will from a release's.
# The update is signed with a throwaway EdDSA key pair that both copies
# trust, so the release key stays in the keychain. With
# DEVELOPER_ID_APPLICATION both copies are signed with it, as a release is.
# Nothing is published, and build/ is left as it was.
#
# Usage: [DEVELOPER_ID_APPLICATION=...] Scripts/try_update.sh
#   It opens the older copy and waits while you choose Check for Updates…
#   in its app menu, then Install Update, then Install and Relaunch.
#   AUTOMATIC=1 instead lets the copy look, download and install on its
#   own, as with both automatic settings on: it installs when it quits,
#   which the script asks it to once the download is done. Nothing needs a
#   click.
# Either way it says whether the copy became the new build, then quits it.
# The copies don't scan when they open, and are given their settings as
# launch arguments; Sparkle saves only that it ran and when it last looked,
# in DevSweep Dev's preferences.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../version.env
source "$root/version.env"
bundle_id="$BUNDLE_ID.dev"

if [[ -n "$(lsappinfo info -only pid "$bundle_id" | sed -n 's/^"pid"=//p')" ]]; then
  echo "try_update.sh: DevSweep Dev is running; quit it first, so the copies don't share an update." >&2
  exit 1
fi

work="$(cd "$(mktemp -d)" && pwd -P)"
server=""

# Asks every copy running from the work folder to quit, as choosing Quit
# would, so Sparkle can install on the way out, and waits for them.
quit_copies() {
  swift - "$work" > /dev/null 2>&1 <<'EOF' || true
import AppKit
let folder = CommandLine.arguments.last!
let copies = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path.hasPrefix(folder) == true }
copies.forEach { $0.terminate() }
for _ in 0..<120 where !copies.allSatisfy(\.isTerminated) {
    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
}
EOF
}
cleanup() {
  quit_copies
  if [[ -n "$server" ]]; then
    kill "$server" 2> /dev/null || true
    wait "$server" 2> /dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

port="$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
feed="http://127.0.0.1:$port"

# A key pair for this run alone: the private half signs the update, the
# public half goes in both copies.
read -r private public < <(swift - <<'EOF'
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
print(key.rawRepresentation.base64EncodedString(), key.publicKey.rawRepresentation.base64EncodedString())
EOF
)

# The new copy, as this checkout builds it, and the older one: the same
# build with a lower build number, as Sparkle's docs suggest, signed again
# around its changed Info.plist with the entitlements it had.
mkdir -p "$work/new" "$work/old" "$work/feed"
new="$(FEED_URL="$feed/appcast.xml" PUBLIC_KEY="$public" OUTPUT="$work/new" "$root/Scripts/package_app.sh" release)"
old="$work/old/$(basename "$new")"
ditto "$new" "$old"
older=$((BUILD_NUMBER - 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $older" "$old/Contents/Info.plist"
codesign --force --sign "${DEVELOPER_ID_APPLICATION:--}" --options runtime --preserve-metadata=entitlements \
  ${DEVELOPER_ID_APPLICATION:+--timestamp} "$old" 2> /dev/null

# The update, as a release zips it, and its appcast, served on this Mac only.
zip="$work/feed/$PRODUCT_NAME-Dev-$MARKETING_VERSION.zip"
(cd "$work/new" && ditto -c -k --norsrc --noextattr --keepParent "$(basename "$new")" "$zip")
SPARKLE_PRIVATE_KEY="$private" PUBLIC_KEY="$public" "$root/Scripts/appcast.sh" "$zip" "$feed" > /dev/null
python3 -I -m http.server "$port" --bind 127.0.0.1 --directory "$work/feed" > "$work/server.log" 2>&1 &
server=$!

# Report mode, and no menu bar item. Automatic: both of Sparkle's settings
# on, and a last check long ago, so it looks as soon as it starts; by hand,
# no question about automatic checks in the way.
args=(-scanOnLaunch NO -showInMenuBar NO)
if [[ -n "${AUTOMATIC:-}" ]]; then
  args+=(-SUEnableAutomaticChecks YES -SUAutomaticallyUpdate YES
    -SULastCheckTime "<date>2000-01-01T00:00:00Z</date>")
else
  args+=(-SUEnableAutomaticChecks NO)
fi
open -n "$old" --args "${args[@]}"
echo "Opened $PRODUCT_NAME Dev $MARKETING_VERSION ($older) from $old, with updates from $feed."
if [[ -z "${AUTOMATIC:-}" ]]; then
  echo "Choose Check for Updates… in its app menu, then Install Update, then Install and Relaunch."
fi

build() { /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$old/Contents/Info.plist" 2> /dev/null || true; }
downloaded=""
for _ in $(seq 1 600); do
  [[ "$(build)" != "$BUILD_NUMBER" ]] || break
  if [[ -n "${AUTOMATIC:-}" && -z "$downloaded" ]] && grep -q "GET /$(basename "$zip")" "$work/server.log"; then
    # Sparkle checks the download and readies the installer, then installs
    # when the app quits.
    downloaded=1
    sleep 10
    quit_copies
  fi
  sleep 1
done

echo "Served:"
sed -n 's/.*"\(GET [^"]*\)".*/  \1/p' "$work/server.log"
if [[ "$(build)" == "$BUILD_NUMBER" ]]; then
  echo "Updated: the copy at $old is now build $BUILD_NUMBER."
else
  echo "try_update.sh: the copy is still build $(build); Console.app's log for Sparkle says why." >&2
  exit 1
fi
