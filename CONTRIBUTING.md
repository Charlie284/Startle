# Contributing to Startle

Contributions are welcome. Safety-sensitive behavior needs especially careful review because Startle deliberately interrupts the user with sudden audiovisual content.

## Before opening a change

- Search existing issues and pull requests.
- Keep changes focused, use public Apple APIs, and preserve the existing Sparkle update path.
- Do not add bundled copyrighted video, telemetry, private APIs, or behavior that bypasses the user's active window or safety settings.
- For a security vulnerability, follow [SECURITY.md](SECURITY.md) instead of opening a public report.

## Development setup

Startle requires macOS 14 or later and Xcode 16 or later.

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

Open `Startle.xcodeproj` to exercise sandbox bookmarks, playback, the global emergency shortcut, and launch-at-login behavior. Swift Package Manager tests alone do not cover those integrations.

## Pull requests

- Add tests for behavior changes and regressions.
- Run the release-mode Swift package tests and the Xcode test action.
- Describe any manual checks, particularly sleep/wake, multiple displays, and emergency dismissal.
- Keep user-facing safety limitations accurate. Do not describe a best-effort check as a guarantee.
- Do not commit local signing identities, team IDs, provisioning profiles, videos, archives, or notarization credentials.

By contributing, you agree that your contribution is licensed under the MIT License.
