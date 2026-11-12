#!/usr/bin/env bash
#
# Signs the app and the command line tool with a Developer ID Application
# identity (hardened runtime, secure timestamp), notarizes both with
# notarytool, staples the ticket to the app, and checks the result.
#
# Usage: Scripts/sign-and-notarize.sh <App.app> <command line tool>
#
# Reads, from the environment:
#   DEVELOPER_ID_APPLICATION  the identity in the keychain, "Developer ID Application: Name (TEAMID)"
#   ASC_KEY_ID                the App Store Connect API key's id
#   ASC_ISSUER_ID             its issuer id
#   ASC_PRIVATE_KEY_P8        the key: a path to AuthKey_<id>.p8, or the file's text
# With any of them missing it says which and exits 3 without changing anything.

set -euo pipefail

app="${1:-}"
cli="${2:-}"
if [[ ! -d "$app" || ! -f "$cli" ]]; then
  sed -n '7p' "${BASH_SOURCE[0]}" | sed 's/^# //' >&2
  exit 2
fi

missing=()
for name in DEVELOPER_ID_APPLICATION ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY_P8; do
  [[ -n "${!name:-}" ]] || missing+=("$name")
done
if (( ${#missing[@]} > 0 )); then
  echo "sign-and-notarize.sh: not signing; missing ${missing[*]}." >&2
  echo "See \"Notarizing\" in docs/releasing.md for what each one is." >&2
  exit 3
fi
if ! security find-identity -v -p codesigning | grep -qF "$DEVELOPER_ID_APPLICATION"; then
  echo "sign-and-notarize.sh: not signing; no identity \"$DEVELOPER_ID_APPLICATION\" in the keychain." >&2
  exit 3
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
key="$ASC_PRIVATE_KEY_P8"
if [[ ! -f "$key" ]]; then
  printf '%s\n' "$ASC_PRIVATE_KEY_P8" > "$work/key.p8"
  key="$work/key.p8"
fi

echo "Signing $cli and $app"
codesign --force --sign "$DEVELOPER_ID_APPLICATION" --options runtime --timestamp "$cli"
codesign --force --sign "$DEVELOPER_ID_APPLICATION" --options runtime --timestamp "$app"
codesign --verify --strict --verbose=2 "$cli"
codesign --verify --deep --strict --verbose=2 "$app"

# The notary service takes zips. A bare tool can't hold a stapled ticket;
# Gatekeeper looks its notarization up online instead.
ditto -c -k --keepParent "$app" "$work/app.zip"
mkdir "$work/cli"
cp "$cli" "$work/cli/"
ditto -c -k --norsrc --noextattr "$work/cli" "$work/cli.zip"

notarize() {
  local zip="$1" result
  echo "Notarizing $(basename "$zip")"
  xcrun notarytool submit "$zip" --key "$key" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
    --wait --output-format json > "$work/result.json"
  result="$(plutil -extract status raw -o - "$work/result.json")"
  if [[ "$result" != "Accepted" ]]; then
    echo "sign-and-notarize.sh: notarization of $(basename "$zip") came back $result" >&2
    xcrun notarytool log "$(plutil -extract id raw -o - "$work/result.json")" \
      --key "$key" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" >&2 || true
    exit 1
  fi
}
notarize "$work/app.zip"
notarize "$work/cli.zip"

xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
echo "Signed, notarized and stapled."
