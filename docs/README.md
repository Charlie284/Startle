# Startle documentation

Startle is a native macOS app that waits in the menu bar and plays a randomly
selected local video at carefully constrained times. These documents describe
how it works and how to develop it safely.

## Contents

- [Architecture](architecture.md) — module map, the path a scare takes from
  timer to screen, and where each piece of state lives.
- [Scheduling](scheduling.md) — schedule modes, active windows, cooldowns,
  daily limits, pauses, and sleep/wake behavior.
- [Video library](video-library.md) — importing videos, security-scoped
  bookmarks, per-video settings, and selection modes.
- [Safety and privacy](safety-and-privacy.md) — every automatic gate that can
  block a scare, the emergency controls, and what Startle can and cannot detect.
- [Updates and releases](updates-and-releases.md) — Sparkle update flow,
  unsigned preview builds, and the signed release gate.
- [Development and testing](development.md) — building, the two test harnesses,
  and which behaviors still need a manual check on a real Mac.

## Reading order

New contributors should read [architecture.md](architecture.md) first, then
[safety-and-privacy.md](safety-and-privacy.md) — most of Startle's design
constraints exist to keep a deliberately startling app under the user's
control. Anyone changing trigger behavior should read
[scheduling.md](scheduling.md) before touching `ScheduleEngine` or
`ScareScheduler`.
