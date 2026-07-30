# Startle

Startle is a native macOS prank/productivity utility that waits in the menu bar and plays a randomly selected local video at carefully constrained times. It is built entirely with SwiftUI, AppKit, AVFoundation, and public Apple frameworks.

[![CI](https://github.com/Charlie284/Startle/actions/workflows/ci.yml/badge.svg)](https://github.com/Charlie284/Startle/actions/workflows/ci.yml)

**Status:** Pre-release. Source builds are available for development and testing. A production download should be published only after completing the signing, notarization, and packaged-app checks in [RELEASE.md](RELEASE.md).

> **Safety:** Do not use Startle on anyone with a heart condition, epilepsy, severe anxiety, PTSD, or sound sensitivity. Obtain clear consent. Never use it where a sudden reaction could cause injury.

## Requirements

- macOS 14 or later
- Xcode 16 or later (the project uses Swift Observation and Swift concurrency)
- A local MP4, MOV, or M4V video; no copyrighted footage is bundled

## Open and run

1. Open `Startle.xcodeproj` in Xcode.
2. Select the **Startle** scheme and your Mac as the run destination.
3. If signing is required, choose your development team under **Signing & Capabilities**.
4. Build and run. Complete onboarding and import a video before enabling scares.

The repository is also a Swift Package. `swift test` builds `StartleCore` and runs the scheduling tests without requiring the Xcode project generator. The executable product can be used for development, though the signed Xcode app is required to validate App Sandbox bookmark and launch-at-login behavior.

## Build and test

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
```

The Xcode target enables App Sandbox and Hardened Runtime. Distribution still requires an Apple Developer signing identity and notarization; project builds and unsigned CI artifacts are not substitutes for those checks.

## Architecture

- `SettingsStore` persists simple and structured preferences through Codable data in UserDefaults.
- `VideoLibrary` creates security-scoped bookmarks, validates AVFoundation playability, stores Codable metadata in Application Support, refreshes stale bookmarks, and flags missing files.
- `ScheduleEngine` is a pure, deterministic scheduling policy layer. It handles random/fixed/chance modes, active windows, overnight ranges, cooldowns, and daily limits.
- `ScareScheduler` owns exactly one cancellable Swift-concurrency timer and always generates a new future schedule after wake.
- `SystemActivityMonitor` watches public sleep/session, camera and microphone device-running state, Apple capture-app activity, full-screen window, display, battery, volume, and idle signals. macOS provides no supported global Focus-state API, and third-party sharing is not always detectable; Startle reports those limitations and does not use private APIs.
- `ScareCoordinator` prevents overlapping scares, selects media, owns security-scope lifetime, records successful scheduled scares, and routes errors.
- `ScareWindowController` preloads AVFoundation media, creates borderless high-level AppKit windows, supports every display mode, maintains aspect ratio or crop-to-fill, captures Escape, restores the cursor and previous app, and removes all observers/resources.
- `EmergencyShortcutManager` registers **Command–Option–Shift–Escape** as a system hot key using the public Carbon hot-key API. Scheduled scares fail closed until that registration succeeds.
- `LaunchAtLoginManager` wraps `SMAppService.mainApp` and respects “Never run at login.”
- SwiftUI views provide onboarding, Dashboard, Videos, Schedule, Safety, Appearance, About, drag-and-drop, per-video controls, and a persistent `MenuBarExtra`.

## Scheduling and wake behavior

Only one scheduling task exists at a time. Disabling scares cancels it. Preference changes cancel and replace it. Eligibility is checked again at firing time, so cooldowns, pauses, daily limits, active windows, and system safety gates cannot be bypassed by an earlier timer. A sleep/session wake discards any overdue trigger and calculates a new date in the future.

## Privacy and permissions

Startle is sandboxed. The file picker grants read-only access only to videos selected by the user; bookmarks preserve that access across launches. Videos are never copied or uploaded. Device-running, Apple screen-capture app, display, battery, output-volume, and window checks use public system APIs. Focus status is unavailable through public macOS APIs, and third-party sharing detection is best-effort.

Startle contains no analytics, advertising SDKs, remote services, or telemetry. Its privacy manifest declares no tracking or collected data. Local file paths and security-scoped bookmark data remain on the Mac.

Automatic safety checks can be incomplete when macOS or another app does not expose the needed state. Read [SAFETY.md](SAFETY.md) before enabling scheduled scares.

## Tests

`Tests/StartleCoreTests/ScheduleEngineTests.swift` covers:

- random interval boundaries
- fixed intervals
- cooldown enforcement
- active days and hours, including overnight windows
- daily limits
- manual pause and system blocks
- sleep/wake future rescheduling
- weekday transitions for overnight windows

Additional tests cover backward-compatible settings decoding, corrupt-settings recovery, and preservation of corrupt video-library data.

Run:

```sh
swift test
```

## Assets

`Assets.xcassets/AppIcon.appiconset` contains the minimal jumpscare-face icon at every required macOS size. The editable square source is retained at `Design/AppIconMaster.svg`, with 1024px PNG and ICNS exports alongside it. Run `Scripts/generate-app-icons.sh` after editing the SVG to refresh every export. `SampleVideoMetadata.json` documents placeholder media metadata; no jumpscare video is included.

## Contributing and releases

- [CONTRIBUTING.md](CONTRIBUTING.md) explains development and pull-request expectations.
- [SECURITY.md](SECURITY.md) explains responsible vulnerability reporting.
- [RELEASE.md](RELEASE.md) defines the signed and notarized release gate.
- [CHANGELOG.md](CHANGELOG.md) tracks user-visible changes.

Startle is available under the [MIT License](LICENSE).
