#!/usr/bin/env bash
#
# Builds what a release ships into dist/: the command line tool and the app,
# each zipped, named with the version from version.env. Signing and
# notarization are Scripts/sign-and-notarize.sh's job; without them the app
# is signed ad hoc.
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

(cd "$dist" && ditto -c -k --norsrc --noextattr "$CLI_NAME" "$CLI_NAME-$MARKETING_VERSION-macos.zip")
(cd "$dist" && ditto -c -k --keepParent "$PRODUCT_NAME.app" "$PRODUCT_NAME-$MARKETING_VERSION.zip")
ls -1 "$dist"/*.zip
