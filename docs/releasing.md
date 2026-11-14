# Releasing

Releases are tag driven: pushing a `v*` tag runs `.github/workflows/release.yml`,
which builds the command line tool and the app, signs and notarizes them when
the signing secrets are set, and publishes a GitHub release with notes from
`CHANGELOG.md` and the appcast the app updates from. Nothing is published
from a laptop.

## Steps

1. **Changelog.** Move the lines under Unreleased in `CHANGELOG.md` into a new
   section, `## 0.5.0`, and leave Unreleased empty.
2. **Version.** Set `MARKETING_VERSION` in `version.env`, and `BUILD_NUMBER` to
   the date and time in UTC, `date -u +%Y%m%d%H%M`: `202611131041` says when
   a build was cut, where a count wouldn't.
3. **Checks.** `make lint test` and `make acceptance DOTFILES=<dotfiles checkout>`.
   Then try an update, as [Updates](#updates) says: `Scripts/try_update.sh`.
   Commit.
4. **Rehearse.** Run the Release workflow by hand; it is a dry run by default:

   ```bash
   gh workflow run release.yml
   ```

   It builds, signs when it can, writes the appcast, and keeps the zips, the
   appcast and the notes as workflow artifacts. Download them, open the app,
   run the tool, read the notes and the appcast.
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

Without the five signing secrets a rehearsal builds the ad hoc build: a
notice on the run says so, and so do the release notes, with how to open an
app that isn't notarized. A tag stops instead, before publishing: an update
has to be notarized, as [Updates](#updates) says. [Notarizing](#notarizing)
lists the secrets and where each value comes from.

## Notarizing

Releases are signed with Developer ID and notarized from 0.5.0 on. This is
what that takes:

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
ticket to the app and checks it with `spctl`. Both zips go to the notary
service before either is waited for. A new team's first submissions can
wait for hours (DevSweep's first took almost six); later ones take minutes.

Locally, the same happens with `make release` when
`DEVELOPER_ID_APPLICATION` (the identity's full name, as
`security find-identity -v -p codesigning` prints it), `ASC_KEY_ID`,
`ASC_ISSUER_ID` and `ASC_PRIVATE_KEY_P8` (the `.p8`'s path) are set. App
Sandbox stays off, and no entitlements are needed: the app reads other
tools' caches and runs simctl and brew. Sparkle's helpers and framework,
inside the app, are signed with the same identity before it.

## Updates

The app updates itself with [Sparkle](https://sparkle-project.org). Every
copy reads the appcast attached to the latest release,
`https://github.com/JaviLorbada/devsweep/releases/latest/download/appcast.xml`,
which offers the newest app zip and the EdDSA signature that proves it came
from here. The command line tool doesn't update itself.

- **The feed and the public key** are `UPDATE_FEED_URL` and
  `UPDATE_PUBLIC_KEY` in `version.env`, which `Scripts/package_app.sh`
  writes into the Info.plist as `SUFeedURL` and `SUPublicEDKey`. A
  development build has no feed. Changing the public key strands every
  installed copy, so it never changes; see the last point.
- **The private key** was made once with Sparkle's `generate_keys --account
  devsweep`, which keeps it in the login keychain of the Mac that made it.
  Keep a copy somewhere safe, such as a password manager: export it with
  `generate_keys --account devsweep -x <file>`, store it, and delete the
  file. The tools are in `.build/artifacts/sparkle/Sparkle/bin` once SwiftPM
  has resolved the package.
- **The secret.** The release workflow reads the private key from
  `SPARKLE_PRIVATE_KEY` in the repository's `release` environment, beside the
  signing secrets, and only its Appcast step sees it:

  ```bash
  generate_keys --account devsweep -x sparkle.key
  gh secret set SPARKLE_PRIVATE_KEY --env release < sparkle.key
  rm sparkle.key
  ```

- **The appcast.** After the build, `Scripts/appcast.sh` runs Sparkle's
  `generate_appcast` on the app zip: one update, its length, its EdDSA
  signature, and this version's section of `CHANGELOG.md` as Markdown, which
  Sparkle's update window shows. `Scripts/check_appcast.swift` then checks
  the signature against `UPDATE_PUBLIC_KEY`, so a wrong secret fails the
  release rather than every copy's update. A tag publishes `appcast.xml` with
  the zips. A tag without the secret, or without notarizing, stops before
  publishing: the release would be the latest, and installed copies would
  find no appcast there.
- **Trying it** before a release, on this Mac: `Scripts/try_update.sh`
  builds this checkout as DevSweep Dev twice, the older copy with a lower
  build number, serves the newer one's zip and appcast on 127.0.0.1, and
  opens the older copy to update from it. It signs the update with a
  throwaway key pair, so the release key stays in the keychain, and with
  `DEVELOPER_ID_APPLICATION` signs both copies as a release is. Choose Check
  for Updates…, Install Update and Install and Relaunch, and it says whether
  the copy became the new build; `AUTOMATIC=1` does the same with no clicks,
  as automatic checks and installs would.
- **Asking first.** The app leaves `SUEnableAutomaticChecks` out, so Sparkle
  asks on the second launch whether to check automatically; Settings >
  General changes the answer. It never sends a system profile.
- **Versions before the updater** can't update themselves: the first release
  that has it says in its notes to download it by hand, and from that one on
  each release updates the one before.
- **If the private key is lost,** a release can still change the EdDSA key,
  because the app is also signed with a Developer ID: Sparkle accepts an
  update that changes one of the two, never both at once. Make a new pair,
  put the new public key in `version.env` and the new private key in the
  secret, and sign that release with the same Developer ID.
