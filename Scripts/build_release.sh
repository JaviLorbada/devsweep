#!/usr/bin/env bash
#
# Builds what a release ships into dist/: the command line tool and the app,
# each zipped, named with the version from version.env. With a Developer ID
# identity and an App Store Connect key in the environment (see
# Scripts/sign-and-notarize.sh) both are signed, notarized and the app
# stapled; without them both are signed ad hoc. dist/signing.txt says which.
#
# Usage: Scripts/build_release.sh

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../version.env
source "$root/version.env"
dist="$root/dist"
rm -rf "$dist"
mkdir -p "$dist"

swift build --package-path "$root" -c release --product "$CLI_NAME" >&2
bin="$(swift build --package-path "$root" -c release --product "$CLI_NAME" --show-bin-path)"
cli="$dist/$CLI_NAME"
cp "$bin/$CLI_NAME" "$cli"
codesign --force --sign "${DEVELOPER_ID_APPLICATION:--}" --options runtime ${DEVELOPER_ID_APPLICATION:+--timestamp} "$cli" >&2

app="$("$root/Scripts/package_app.sh" release)"
cp -R "$app" "$dist/"

# Signed and notarized when the credentials are there; ad hoc otherwise.
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_PRIVATE_KEY_P8:-}" ]]; then
  "$root/Scripts/sign-and-notarize.sh" "$dist/$PRODUCT_NAME.app" "$cli" >&2
  echo "notarized" > "$dist/signing.txt"
else
  echo "ad hoc" > "$dist/signing.txt"
fi

(cd "$dist" && ditto -c -k --norsrc --noextattr "$CLI_NAME" "$CLI_NAME-$MARKETING_VERSION-macos.zip")
(cd "$dist" && ditto -c -k --keepParent "$PRODUCT_NAME.app" "$PRODUCT_NAME-$MARKETING_VERSION.zip")
ls -1 "$dist"/*.zip
