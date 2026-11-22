# Updates and releases

## In-app updates (Sparkle)

`SoftwareUpdater` wraps Sparkle's `SPUStandardUpdaterController` (Sparkle
2.9.4+ via SPM) and observes `canCheckForUpdates`. The app exposes
**Check for Updates…** from the app menu, the menu-bar menu, and the About
screen.

- The feed is `SUFeedURL` in `Config/Info.plist`, currently the `appcast.xml`
  asset attached to a fixed `appcast` GitHub release in this repository.
- Sparkle's sandboxed downloader and installer services do the work — that is
  what the `mach-lookup` entitlement exception in
  `Config/Startle.entitlements` is for.
- Update archives are verified with the project's Ed25519 release key before
  installation; a tampered download never reaches the installer.

## Preview (unsigned) builds

Tags matching `v*` run `.github/workflows/release.yml`, which lints property
lists, runs both test suites, builds a universal app, and publishes a GitHub
**prerelease** with a DMG (recommended), a ZIP, and SHA-256 checksums. These
builds are unsigned — there is no paid Apple Developer identity on the
project — so macOS reports an unidentified developer and the first launch
needs **Control-click → Open**. An unsigned preview is not a substitute for a
signed, notarized release.

## The signed release gate

[RELEASE.md](../RELEASE.md) defines the bar a production download must clear:
signing, notarization, and packaged-app verification via the scripts in
`Scripts/` (`verify-unsigned-build.sh`, `verify-distribution.sh`,
`package-unsigned-release.sh`). A separate release-environment job signs the
update ZIP with Sparkle's Ed25519 key and replaces the fixed `appcast` asset
that installed copies poll. The private key lives only in the `release`
environment's `SPARKLE_PRIVATE_KEY` secret and the release operator's
Keychain — never in the repo.

## App icons

`Design/AppIconMaster.svg` is the editable source. After editing it, run
`Scripts/generate-app-icons.sh` to regenerate every `AppIcon.appiconset`
export plus the 1024 px PNG and ICNS alongside it.
