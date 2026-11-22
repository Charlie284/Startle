# Safety and privacy

Startle exists to startle the user, so the codebase treats "should this
interruption happen right now?" as a fail-closed question for arming and
triggering: scares cannot be enabled without onboarding, an enabled video,
and a working emergency shortcut, and every firing re-validates the live
gates. Read [SAFETY.md](../SAFETY.md) for the user-facing rules; this page
documents the machinery behind them.

## Emergency controls

- **Escape** closes an active scare. The scare window captures it in
  `keyDown`, so it works even while a borderless full-screen window is up.
- **Command–Option–Shift–Escape** closes the active scare *and* disables
  future scares. It is a real global hot key registered through the public
  Carbon `RegisterEventHotKey` API (`EmergencyShortcutManager`), so it works
  while another app is frontmost.
- **Fail-closed arming:** scheduled scares cannot be enabled until hot-key
  registration succeeds. If another app holds the shortcut, Startle reports
  the conflict and stays unarmed until registration is retried from Safety.
  The same check re-runs at launch — if onboarding is incomplete, no enabled
  video exists, or the shortcut is unregistered, `scaresEnabled` is forced
  off.

## Automatic gates

`SystemActivityMonitor` maintains a live snapshot and `SafetyPolicy.blockReason`
turns it into the first blocking reason, in this order:

| Reason | Signal | Gate |
| --- | --- | --- |
| `asleepOrLocked` | `NSWorkspace` sleep + session notifications | Always blocks |
| `screenCapture` | Apple screen-sharing/capture processes running | `pauseForScreenCapture` (default on) |
| `fullScreenApp` | Frontmost window's bounds match a display | `pauseForFullScreenApps` (default on) |
| `cameraOrMicrophone` | CMIO camera / CoreAudio input device `IsRunningSomewhere` | `pauseForCameraOrMicrophone` (default on) |
| `externalDisplay` | More than one `NSScreen` | `disableWithExternalDisplay` (default off) |
| `lowBattery` | IOKit power sources below `disableBelowBatteryPercent` (default 15%) | Always on |
| `highVolume` | Default output device volume above `disableAboveSystemVolumePercent` (default 85%) | Always on |
| `idleReturnGracePeriod` | Input idle > 5 min, then returned within `idleGracePeriod` (default 5 min) | `avoidAfterIdle` (default on) |

Sensor reads that fail fall back to permissive defaults rather than blocking:
a battery query failure substitutes 100% and an output-volume query failure
substitutes 0%, so the `lowBattery` and `highVolume` gates pass when their
signal is unavailable. Most signals refresh on a 15 s poll; sleep and session
changes arrive as workspace notifications. The gates are re-evaluated **three times** per scare:
by the scheduler at firing time, by the coordinator before picking media, and
once more in the window controller's `preflight` immediately before playback
begins.

Separately, the **app exclusion list** (`excludedApplications`, matched on
bundle identifier via `NSWorkspace.frontmostApplication`) is checked right
before presentation and again after the bookmark resolves. It uses no
Accessibility permission. Presentations, call, recording, and editing apps
belong on it.

## Presentation-time controls

- **Quiet Mode** (`quietMode`) silences playback and the countdown beep —
  the scare is visual only.
- **Countdown** (`countdownSeconds`) shows a large numeric countdown before
  playback, so even a "scare" can arrive with a warning.
- A **presentation watchdog** (countdown + trimmed duration + 30 s) and a
  **stall watchdog** guarantee the windows always come down even if playback
  hangs; `finish` restores the cursor and the previously frontmost app and
  removes all observers.
- **Never run at login** (`neverRunAtLogin`, default on) unregisters the app
  from `SMAppService` even if the user enabled launch-at-login, and the two
  states are reconciled at launch.

## Known detection limits

These are real limits of public macOS APIs, documented in-app and in
[SAFETY.md](../SAFETY.md):

- There is **no supported API for Focus / Do Not Disturb state**. The
  `pauseForFocus` settings key is kept for file compatibility but is always
  decoded as `false`.
- Third-party screen sharing (Zoom, Meet, Teams) is not reliably detectable;
  only Apple's own capture activity is watched. The camera/microphone
  device-running check is the best proxy.
- All detection is best-effort: it reduces risk but does not replace consent
  or supervision. Startle is not a safety device.

## Privacy posture

- **Sandboxed** (`com.apple.security.app-sandbox`) with only a mach-lookup
  exception for Sparkle's helper services. Hardened Runtime is on.
- Videos are read in place through security-scoped bookmarks — never copied,
  never uploaded.
- **No analytics, ads, or telemetry.** The only network traffic is Sparkle
  update checks/downloads against the signed GitHub release feed. The privacy
  manifest declares no collected data and no tracking.
- The 50-event activity history stores video display names and excluded-app
  names — never file paths — and can be cleared from the dashboard.
