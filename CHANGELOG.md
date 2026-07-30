# Changelog

All notable changes will be documented here. The project follows [Semantic Versioning](https://semver.org/).

## Unreleased

## 1.0.1 - 2026-07-29

### Added

- Compressed DMG release downloads with an Applications shortcut.

## 1.0.0 - 2026-07-29

### Added

- Tag-driven unsigned macOS prereleases with SHA-256 checksums.
- Release-mode CI for the Swift package and Xcode project.
- Settings migration and corrupt-data recovery coverage.
- Privacy, security, contribution, safety, and release documentation.
- A privacy manifest declaring app-only settings storage and no data collection or tracking.
- A distribution verifier for Developer ID signing, Hardened Runtime, sandbox entitlements, Gatekeeper, notarization, and the bundled privacy manifest.
- CI verification that the universal Release app embeds and can locate its framework dependencies.
- Explicit reporting when the global emergency shortcut cannot be registered.
- Fail-closed arming and an in-app retry when the global emergency shortcut is unavailable.

### Fixed

- Overnight active windows now continue into the following calendar day.
- Corrupt video-library data is preserved instead of being overwritten at launch.
- Launch-at-login errors can be dismissed normally.
- Countdown tasks cannot affect a later playback session.
- Release builds now include the runpath required to load the embedded StartleCore framework outside Xcode.

### Changed

- Focus status is shown as unavailable instead of exposing a control that macOS cannot support through public APIs.
- Error details that may contain local paths are private in system logs.
