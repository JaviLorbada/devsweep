#!/usr/bin/env bash
#
# For CI: creates a throwaway keychain, imports the Developer ID Application
# certificate from a base64 .p12 into it, lets codesign use it without a
# prompt, and prints the identity's name. The runner's temp folder, and the
# keychain with it, are gone when the job ends; --delete removes it sooner.
#
# Usage: Scripts/setup_keychain.sh            reads MACOS_SIGNING_P12 and MACOS_SIGNING_P12_PASSWORD
#        Scripts/setup_keychain.sh --delete

set -euo pipefail

keychain="${RUNNER_TEMP:-$(mktemp -d)}/release-signing.keychain-db"

if [[ "${1:-}" == "--delete" ]]; then
  security delete-keychain "$keychain" 2>/dev/null || true
  exit 0
fi

: "${MACOS_SIGNING_P12:?the base64 .p12 is not set}"
: "${MACOS_SIGNING_P12_PASSWORD:?the .p12 password is not set}"

password="$(uuidgen)"
certificate="$(mktemp)"
trap 'rm -f "$certificate"' EXIT
printf '%s' "$MACOS_SIGNING_P12" | base64 --decode > "$certificate"

security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$certificate" -k "$keychain" -P "$MACOS_SIGNING_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" > /dev/null
# shellcheck disable=SC2046
security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')

security find-identity -v -p codesigning "$keychain" | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' | head -1
