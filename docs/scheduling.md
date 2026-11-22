# Scheduling

Scheduling is split in two: `ScheduleEngine` is a pure, stateless policy
layer, and `ScareScheduler` owns the single live timer that applies it.

## Schedule modes

| Mode | Behavior | Settings used |
| --- | --- | --- |
| `randomInterval` | Next trigger is a uniform random offset between the minimum and maximum interval. | `minimumInterval`, `maximumInterval` (defaults 30–90 min) |
| `fixedInterval` | Next trigger is exactly the fixed interval away (clamped to ≥ 60 s). | `fixedInterval` (default 60 min) |
| `randomChance` | A check fires every `chanceCheckInterval`; each check triggers a scare with probability `chancePercent`%. | `chanceCheckInterval` (default 5 min), `chancePercent` (default 15) |

In every mode the candidate trigger time is pushed forward by
`advanceToActiveWindow` until it lands inside an active window.

## Active windows

- `activeDays` is a set of `Calendar` weekday numbers (1 = Sunday … 7 =
  Saturday, all on by default).
- `activeStartMinutes` / `activeEndMinutes` are minutes since midnight
  (default 09:00–22:00).
- Start earlier than end means a same-day window; start later than end means
  an **overnight window** — a time before `activeEndMinutes` belongs to the
  previous day's window, so "Fri 20:00 → Sat 02:00" requires Friday to be an
  active day.
- Equal start and end means the whole day is active (only the day filter
  applies).

## Eligibility gates

`ScheduleEngine.isEligible` requires all of:

- not system-blocked,
- inside the active window,
- `scaresToday < maximumScaresPerDay` (default 5),
- no future `pauseUntil` deadline,
- cooldown elapsed since `lastScareDate` (default 30 min).

These are evaluated **again at firing time** by
`ScareScheduler.currentStatus`, plus the live safety snapshot from
`SystemActivityMonitor` (see
[safety-and-privacy.md](safety-and-privacy.md)). A timer set hours earlier can
never fire into a condition that appeared since.

## The single timer

`ScareScheduler` keeps exactly one cancellable `Task`:

- `reschedule()` cancels any existing task, clears `nextTriggerDate`, computes
  a fresh date with a new RNG, and sleeps until it.
- It runs on enable, on any settings change, after every firing (in a `defer`),
  and on every system wake.
- When the Mac sleeps or the session resigns active, `onSuspend` dismisses any
  visible scare; on wake, `onWake` reschedules — an overdue trigger is
  discarded rather than fired late.

## Pauses

`pauseUntil` (a `Date?`) suspends eligibility until the deadline passes; the
dashboard exposes preset and custom durations plus "pause until the next
active window", which uses `nextActiveWindowStart` to find the next day/time
combination in the coming week.

## What gets recorded

Every firing attempt that does not reach the screen produces a `skipped`
activity event with a reason: paused, outside the active window, daily limit,
cooldown, a specific `SafetyBlockReason`, an excluded frontmost app, chance
not selected, or no eligible video. These land in the 50-event activity
history shown on the dashboard.
