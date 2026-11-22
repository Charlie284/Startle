# Video library

`VideoLibrary` manages the user's imported videos. Videos are never copied
into the app container: the library stores a security-scoped bookmark per
video plus Codable metadata in
`~/Library/Application Support/Startle/VideoLibrary.json` (with a
`VideoLibrary.recovery.json` fallback when the main file is corrupt).

## Importing

- Supported extensions: `mp4`, `mov`, `m4v`.
- Each candidate is validated as a playable `AVAsset` with a finite, positive
  duration before a `VideoItem` is created.
- Duplicates are detected by `lastKnownPath`.
- The bookmark is created with `.withSecurityScope`; the file picker grants
  read-only access to exactly the files the user chose, and the bookmark
  preserves that access across launches inside the sandbox.

## Bookmarks and missing files

`resolve(_:)` turns a bookmark back into a URL at playback time:

- If the bookmark resolves but is stale, a fresh bookmark and the new path are
  saved.
- If it cannot be resolved, or the file no longer exists, the item is marked
  `isMissing` and playback throws `StartleError.videoUnavailable`.
- Missing videos are excluded from `enabledVideos` and can be re-linked to a
  new file (`relink`, which preserves trim settings clamped to the new
  duration) or purged with `removeMissingVideos`.

Security-scope access is started on resolve and stopped by the caller —
`ScareCoordinator` wraps the entire presentation so the scope is held exactly
as long as it is needed, including on every early-return path.

## Per-video settings

`VideoItem` carries playback and selection fields, normalized by
`normalizePlaybackSettings` (clamping out-of-range values):

| Field | Effect |
| --- | --- |
| `isEnabled` | Excluded from `enabledVideos` when off; "disable all" also skips missing items |
| `volume` | 0–1, applied to the player (ignored in Quiet Mode) |
| `trimStart` / `trimEnd` | Playback window inside the video; `effectiveTrim*` accessors clamp it to `[0, duration]` with a 10 ms minimum |
| `selectionWeight` | 0.1–10 multiplier in weighted-random mode |
| `isRare` | Multiplies the effective weight by 0.1 — a "rare" video is ten times less likely at the same weight |
| `selectionCooldown` | Minimum time between plays of this video, up to 30 days; enforced by `isEligible(at:)` against `lastPlayedAt` |

## Selection modes

`VideoSelectionSettings.mode`:

- **`weightedRandom`** — pick among eligible videos proportionally to
  `effectiveSelectionWeight`.
- **`shuffleBag`** — uniform draws without replacement until the bag empties,
  then it refills.

Both modes first drop the last `recentHistoryCount` played videos (default 4;
the library keeps a 5-deep `recentVideoIDs` list). If every candidate is on a
per-video `selectionCooldown`, `nextVideoEligibilityDate` reports when the
earliest one becomes eligible and the scare is skipped as `noEligibleVideo`.

If no enabled videos remain — on import changes or at launch — the app
disables scares entirely (fail-closed).
