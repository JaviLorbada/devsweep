# Releasing

Releases are tag driven: pushing a `v*` tag runs `.github/workflows/release.yml`,
which builds the command line tool and the app, signs and notarizes them when
the signing secrets are set, and publishes a GitHub release with notes from
`CHANGELOG.md`. Nothing is published from a laptop.

## Steps

1. **Changelog.** Move the lines under Unreleased in `CHANGELOG.md` into a new
   section, `## 0.2.0`, and leave Unreleased empty.
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
   git tag v0.2.0
   git push origin v0.2.0
   ```

6. **Homebrew.** In the tap, set the formula's `url` and `sha256` to the
   release's source tarball and the cask's `version` and `sha256` to the app
   zip; templates are in `packaging/`.

   ```bash
   curl -sL https://github.com/JaviLorbada/devsweep/archive/refs/tags/v0.2.0.tar.gz | shasum -a 256
   shasum -a 256 DevSweep-0.2.0.zip
   ```

## Locally

`make release` builds the same zips into `dist/`. With `DEVELOPER_ID_APPLICATION`,
`ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY_P8` in the environment it
signs and notarizes them too; see "Notarizing a release" in the README.

## Signing

Without the five signing secrets the workflow ships the ad hoc build: a
notice on the run says so, and so do the release notes, with how to open an
app that isn't notarized. The secrets and where each value comes from are
listed in the README.

## Updates

There is no in-app updater yet. When there is one (Sparkle), it goes here:
an EdDSA key pair whose private half is a repository secret, the appcast
generated and published by the release workflow after the zip, and the feed
URL and public key in the Info.plist that `Scripts/package_app.sh` writes.
