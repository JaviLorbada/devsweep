# Releasing

Releases are tag driven: pushing a `v*` tag runs `.github/workflows/release.yml`,
which builds the command line tool and the app, signs and notarizes them when
the signing secrets are set, and publishes a GitHub release with notes from
`CHANGELOG.md`. Nothing is published from a laptop.

## Steps

1. **Changelog.** Move the lines under Unreleased in `CHANGELOG.md` into a new
   section, `## 0.5.0`, and leave Unreleased empty.
2. **Version.** Set `MARKETING_VERSION` and bump `BUILD_NUMBER` in `version.env`.
3. **Checks.** `make lint test` and `make acceptance DOTFILES=<dotfiles checkout>`.
   Commit.
4. **Rehearse.** Run the Release workflow by hand; it is a dry run by default:

   ```bash
   gh workflow run release.yml
   ```

   It builds, signs when it can, and keeps the zips and the notes as workflow
   artifacts. Download them, open the app, run the tool, read the notes.
5. **Tag.** The workflow refuses a tag that doesn't match `version.env`:

   ```bash
   git tag -a v0.5.0 -m "DevSweep 0.5.0"
   git push origin v0.5.0
   ```

6. **Homebrew.** In the tap, set the formula's `url` and `sha256` to the
   release's source tarball and the cask's `version` and `sha256` to the app
   zip; templates are in `packaging/`.

   ```bash
   curl -sL https://github.com/JaviLorbada/devsweep/archive/refs/tags/v0.5.0.tar.gz | shasum -a 256
   shasum -a 256 DevSweep-0.5.0.zip
   ```

## Locally

`make release` builds the same zips into `dist/`. With `DEVELOPER_ID_APPLICATION`
in the environment, and either `NOTARY_KEYCHAIN_PROFILE` (a profile saved with
`xcrun notarytool store-credentials`) or `ASC_KEY_ID`, `ASC_ISSUER_ID` and
`ASC_PRIVATE_KEY_P8`, it signs and notarizes them too; see
[Notarizing](#notarizing).

## Signing

Without the five signing secrets the workflow ships the ad hoc build: a
notice on the run says so, and so do the release notes, with how to open an
app that isn't notarized. [Notarizing](#notarizing) lists the secrets and
where each value comes from.

## Notarizing

Until this is set up, releases are signed ad hoc, not notarized, and the
release notes say so. Everything is in place for the day it is:

1. **Apple Developer Program** membership, for a Developer ID.
2. **A Developer ID Application certificate**: create it in Xcode (Settings >
   Accounts > Manage Certificates) or on developer.apple.com, then export it
   from Keychain Access with its private key as a `.p12`, with a password.
3. **An App Store Connect API key** for notarization: App Store Connect >
   Users and Access > Integrations > App Store Connect API, a key with the
   Developer role. Note its **Key ID** and the **Issuer ID** above the list,
   and download the `AuthKey_<KeyID>.p8` file (it can be downloaded once).
4. **GitHub secrets**, in the repository's `release` environment (Settings >
   Environments), so only the release job can read them:

   | Secret | Value |
   |---|---|
   | `MACOS_SIGNING_P12` | the `.p12`, base64: `base64 -i DeveloperID.p12 \| pbcopy` |
   | `MACOS_SIGNING_P12_PASSWORD` | the `.p12`'s password |
   | `ASC_KEY_ID` | the Key ID |
   | `ASC_ISSUER_ID` | the Issuer ID |
   | `ASC_PRIVATE_KEY_P8` | the text of the `.p8` file |

With all five set, the release workflow signs both the app and the tool with
the hardened runtime and a secure timestamp, notarizes them, staples the
ticket to the app and checks it with `spctl`. Locally, the same happens with
`make release` when `DEVELOPER_ID_APPLICATION` (the identity's full name, as
`security find-identity -v -p codesigning` prints it), `ASC_KEY_ID`,
`ASC_ISSUER_ID` and `ASC_PRIVATE_KEY_P8` (the `.p8`'s path) are set. App
Sandbox stays off, and no entitlements are needed: the app reads other
tools' caches and runs simctl and brew.

## Updates

There is no in-app updater yet. When there is one (Sparkle), it goes here:
an EdDSA key pair whose private half is a repository secret, the appcast
generated and published by the release workflow after the zip, and the feed
URL and public key in the Info.plist that `Scripts/package_app.sh` writes.
