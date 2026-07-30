# Release process

Startle is not ready to distribute merely because `swift test` passes. A release must also be archived, signed, notarized, and exercised as the packaged sandboxed app.

## Unsigned preview releases

Pushing a version tag such as `v1.0.0` runs `.github/workflows/release.yml`. The workflow repeats the source and Xcode tests, builds a universal macOS app, verifies the unsigned bundle, and publishes a prerelease ZIP with its SHA-256 checksum.

Unsigned previews are intended for development and evaluation. Gatekeeper will identify them as coming from an unidentified developer, and they do not satisfy the production release process below.

## 1. Prepare the version

1. Start from a clean default branch with passing CI.
2. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project.
3. Move the relevant entries from `Unreleased` in `CHANGELOG.md` into a versioned section.
4. Confirm the safety, privacy, and compatibility statements still match the implementation.

## 2. Run automated gates

```sh
swift test -c release -Xswiftc -warnings-as-errors

xcodebuild \
  -project Startle.xcodeproj \
  -scheme Startle \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  test

xcodebuild \
  -project Startle.xcodeproj \
  -scheme Startle \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  build

./Scripts/verify-unsigned-build.sh build/DerivedData/Build/Products/Release/Startle.app
```

The unsigned-bundle verifier checks the embedded framework, runpath, architectures, property list, and privacy manifest. It does not prove signing, entitlements, sandbox behavior, or Gatekeeper acceptance.

## 3. Archive and notarize

Configure the Startle target with the appropriate Apple Developer team and a Developer ID Application certificate. Do not commit a personal or organization-specific team ID.

Create a Release archive in Xcode and choose **Distribute App → Developer ID → Upload**. Hardened Runtime and App Sandbox must remain enabled. After notarization, staple the ticket to the exported app or disk image.

For a command-line notarization workflow, store credentials in a Keychain profile and use `xcrun notarytool`; never place credentials in this repository.

Run the verifier against the final exported app:

```sh
./Scripts/verify-distribution.sh /path/to/Startle.app
```

## 4. Manual release matrix

Exercise the final signed artifact on a clean account on macOS 14 and the current macOS release:

- onboarding and import via picker and drag-and-drop
- bookmark restoration after relaunch and after moving or deleting a video
- MP4, MOV, and M4V playback; trim, volume, quiet mode, and countdown
- Escape and the global emergency shortcut, including a deliberate shortcut conflict
- random, fixed, chance, daytime, overnight, cooldown, pause, and daily-limit scheduling
- sleep/wake, lock/unlock, idle return, camera/microphone use, and screen capture
- full-screen, centered, current-display, and all-display modes
- cursor and previous-application restoration after completion, failure, and dismissal
- launch-at-login enablement and the “Never run at login” override
- recovery from corrupt settings and video-library files

## 5. Publish

1. Verify the stapled artifact with `Scripts/verify-distribution.sh`.
2. Create a signed version tag.
3. Publish release notes from `CHANGELOG.md` and attach the notarized artifact plus its SHA-256 checksum.
4. Install the downloaded artifact once more and repeat a short smoke test before announcing the release.
