# Development and testing

## Requirements

- macOS 14 or later, Xcode 16 or later (Swift Observation and Swift
  concurrency are used throughout).
- No bundled video: supply your own MP4/MOV/M4V for manual testing.

## Two test harnesses

**SwiftPM tests** — run anywhere, no Xcode project needed:

```sh
swift test -c release -Xswiftc -warnings-as-errors
```

`Tests/StartleCoreTests/` covers the parts of the app that were designed to
be pure or injectable:

- `ScheduleEngineTests` — interval boundaries, fixed intervals, chance mode,
  active days/hours including overnight windows, cooldowns, daily limits,
  pauses, sleep/wake rescheduling, weekday transitions.
- `SettingsStoreTests` — backward-compatible settings decoding and
  corrupt-settings recovery.
- `SafetyPolicyTests` — the block-reason policy against synthetic
  `SystemActivitySnapshot`s.
- `VideoLibraryTests` — bookmark metadata, missing-file handling, relinking,
  selection modes and cooldowns, corrupt-library recovery.

**Xcode tests** — required for the sandboxed integrations:

```sh
xcodebuild \
  -project Startle.xcodeproj \
  -scheme Startle \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  test
```

Formatting and plist validity are part of CI:
`xcrun swift-format lint --recursive --strict Sources Tests Package.swift`
plus `plutil -lint` on `Config/Info.plist`, `Config/Startle.entitlements`,
and `Sources/StartleApp/Resources/PrivacyInfo.xcprivacy`.

## What tests cannot cover

Some behaviors only exist on a real logged-in session and need manual
verification — call them out in your PR when you touch nearby code:

- Security-scoped bookmark resolution across relaunches (needs the sandboxed
  app, not SPM).
- The global emergency hot key and shortcut conflicts with other apps.
- Launch-at-login registration and the `requiresApproval` state.
- Sleep/wake rescheduling, locked-session dismissal, multiple displays.
- Actual AVPlayer presentation: countdown, watchdogs, cursor/app restore.
- Sparkle update install and relaunch (test against a private appcast, not
  the live feed).

## Conventions worth knowing

- Public Apple APIs only; no private API use anywhere.
- Core managers are `@MainActor @Observable`; policy types
  (`ScheduleEngine`, `SafetyPolicy`, models) are pure `Sendable` structs —
  keep new logic testable the same way, with injectable clocks/RNG where
  randomness or time is involved.
- Never describe a best-effort detection as a guarantee in user-facing text,
  and keep [SAFETY.md](../SAFETY.md) and
  [safety-and-privacy.md](safety-and-privacy.md) in sync with the checks the
  code actually performs.
- Do not commit signing identities, team IDs, provisioning profiles, videos,
  archives, or notarization credentials. See
  [CONTRIBUTING.md](../CONTRIBUTING.md).
