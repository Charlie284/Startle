import Foundation
import XCTest

@testable import StartleCore

final class ScheduleEngineTests: XCTestCase {
  private let engine = ScheduleEngine()
  private var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0)!
    return value
  }

  func testRandomIntervalStaysWithinBounds() throws {
    var settings = allDaySettings()
    settings.mode = .randomInterval
    settings.minimumInterval = 600
    settings.maximumInterval = 1200
    let now = date(2026, 7, 14, 12, 0)
    var rng = SeededRNG(seed: 42)
    for _ in 0..<100 {
      let next = try XCTUnwrap(
        engine.nextTriggerDate(
          after: now, settings: settings, using: &rng, calendar: calendar))
      XCTAssertGreaterThanOrEqual(next.timeIntervalSince(now), 600)
      XCTAssertLessThanOrEqual(next.timeIntervalSince(now), 1200)
    }
  }

  func testFixedIntervalIsExact() {
    var settings = allDaySettings()
    settings.mode = .fixedInterval
    settings.fixedInterval = 3600
    let now = date(2026, 7, 14, 12, 0)
    var rng = SeededRNG(seed: 1)
    XCTAssertEqual(
      engine.nextTriggerDate(after: now, settings: settings, using: &rng, calendar: calendar),
      now.addingTimeInterval(3600))
  }

  func testEmptyActiveDaysProducesNoTrigger() {
    var settings = allDaySettings()
    settings.activeDays = []
    let now = date(2026, 7, 14, 12, 0)
    var rng = SeededRNG(seed: 1)

    XCTAssertNil(
      engine.nextTriggerDate(after: now, settings: settings, using: &rng, calendar: calendar))
  }

  func testNextActiveWindowStartFindsLaterTodayAndNextSelectedDay() throws {
    var settings = allDaySettings()
    settings.activeDays = [3, 5]
    settings.activeStartMinutes = 9 * 60
    settings.activeEndMinutes = 17 * 60

    XCTAssertEqual(
      engine.nextActiveWindowStart(
        after: date(2026, 7, 14, 8, 0), settings: settings, calendar: calendar),
      date(2026, 7, 14, 9, 0))
    XCTAssertEqual(
      engine.nextActiveWindowStart(
        after: date(2026, 7, 14, 10, 0), settings: settings, calendar: calendar),
      date(2026, 7, 16, 9, 0))
  }

  func testNextActiveWindowStartUsesMidnightForAllDayWindows() {
    var settings = allDaySettings()
    settings.activeDays = [4]

    XCTAssertEqual(
      engine.nextActiveWindowStart(
        after: date(2026, 7, 14, 10, 0), settings: settings, calendar: calendar),
      date(2026, 7, 15, 0, 0))
  }

  func testCooldownBlocksUntilElapsed() {
    var settings = allDaySettings()
    settings.cooldown = 1800
    let now = date(2026, 7, 14, 12, 0)
    XCTAssertFalse(
      engine.isEligible(
        context: .init(now: now, lastScare: now.addingTimeInterval(-1799), scaresToday: 1),
        settings: settings, calendar: calendar))
    XCTAssertTrue(
      engine.isEligible(
        context: .init(now: now, lastScare: now.addingTimeInterval(-1800), scaresToday: 1),
        settings: settings, calendar: calendar))
  }

  func testActiveHoursAndDaysAreEnforced() {
    var settings = allDaySettings()
    settings.activeDays = [3]
    settings.activeStartMinutes = 9 * 60
    settings.activeEndMinutes = 22 * 60
    XCTAssertTrue(
      engine.isWithinActiveWindow(date(2026, 7, 14, 9, 0), settings: settings, calendar: calendar))
    XCTAssertTrue(
      engine.isWithinActiveWindow(date(2026, 7, 14, 21, 59), settings: settings, calendar: calendar)
    )
    XCTAssertFalse(
      engine.isWithinActiveWindow(date(2026, 7, 14, 22, 0), settings: settings, calendar: calendar))
    XCTAssertFalse(
      engine.isWithinActiveWindow(date(2026, 7, 15, 12, 0), settings: settings, calendar: calendar))
  }

  func testOvernightActiveWindowCrossesMidnight() {
    var settings = allDaySettings()
    settings.activeDays = [3]
    settings.activeStartMinutes = 22 * 60
    settings.activeEndMinutes = 6 * 60
    XCTAssertTrue(
      engine.isWithinActiveWindow(date(2026, 7, 14, 23, 0), settings: settings, calendar: calendar))
    XCTAssertTrue(
      engine.isWithinActiveWindow(date(2026, 7, 15, 5, 59), settings: settings, calendar: calendar))
    XCTAssertFalse(
      engine.isWithinActiveWindow(date(2026, 7, 14, 5, 59), settings: settings, calendar: calendar))
    XCTAssertFalse(
      engine.isWithinActiveWindow(date(2026, 7, 14, 12, 0), settings: settings, calendar: calendar))
  }

  func testOvernightWindowWrapsFromSaturdayIntoSunday() {
    var settings = allDaySettings()
    settings.activeDays = [7]
    settings.activeStartMinutes = 22 * 60
    settings.activeEndMinutes = 6 * 60

    XCTAssertTrue(
      engine.isWithinActiveWindow(date(2026, 7, 18, 23, 0), settings: settings, calendar: calendar))
    XCTAssertTrue(
      engine.isWithinActiveWindow(date(2026, 7, 19, 2, 0), settings: settings, calendar: calendar))
    XCTAssertFalse(
      engine.isWithinActiveWindow(date(2026, 7, 20, 2, 0), settings: settings, calendar: calendar))
  }

  func testDailyLimitPreventsScare() {
    var settings = allDaySettings()
    settings.maximumScaresPerDay = 3
    XCTAssertFalse(
      engine.isEligible(
        context: .init(now: date(2026, 7, 14, 12, 0), lastScare: nil, scaresToday: 3),
        settings: settings, calendar: calendar))
  }

  func testSleepWakeRescheduleAlwaysCreatesNewFutureDate() throws {
    var settings = allDaySettings()
    settings.mode = .fixedInterval
    settings.fixedInterval = 900
    let wake = date(2026, 7, 14, 12, 0)
    var rng = SeededRNG(seed: 7)
    let replacement = try XCTUnwrap(
      engine.nextTriggerDate(
        after: wake, settings: settings, using: &rng, calendar: calendar))
    XCTAssertEqual(replacement, wake.addingTimeInterval(900))
    XCTAssertGreaterThan(replacement, wake)
  }

  @MainActor
  func testSchedulerReplacesPendingDateAfterWake() throws {
    let suiteName = "StartleCoreTests.ScareScheduler.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = SettingsStore(defaults: defaults)
    settings.values.onboardingCompleted = true
    settings.values.schedule = allDaySettings()
    settings.values.schedule.mode = .fixedInterval
    settings.values.schedule.fixedInterval = 900
    try settings.setEnabled(true, hasVideos: true, emergencyShortcutAvailable: true)
    let activity = SystemActivityMonitor()
    let scheduler = ScareScheduler(settings: settings, activity: activity)
    let originalBase = Date()
    scheduler.reschedule(after: originalBase)
    let original = try XCTUnwrap(scheduler.nextTriggerDate)
    let wake = originalBase.addingTimeInterval(60)

    scheduler.reschedule(after: wake)

    XCTAssertEqual(original.timeIntervalSince(originalBase), 900, accuracy: 0.001)
    XCTAssertEqual(
      try XCTUnwrap(scheduler.nextTriggerDate).timeIntervalSince(wake), 900, accuracy: 0.001)
  }

  func testPauseAndSystemBlockPreventScare() {
    let settings = allDaySettings()
    let now = date(2026, 7, 14, 12, 0)
    XCTAssertFalse(
      engine.isEligible(
        context: .init(now: now, lastScare: nil, scaresToday: 0, isSystemBlocked: true),
        settings: settings, calendar: calendar))
    XCTAssertFalse(
      engine.isEligible(
        context: .init(
          now: now, lastScare: nil, scaresToday: 0, pauseUntil: now.addingTimeInterval(60)),
        settings: settings, calendar: calendar))
  }

  @MainActor
  func testSchedulerReportsPauseAndRecordsSkippedCheck() async throws {
    let suiteName = "StartleCoreTests.ScareScheduler.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = SettingsStore(defaults: defaults)
    settings.values.onboardingCompleted = true
    settings.values.schedule = allDaySettings()
    try settings.setEnabled(true, hasVideos: true, emergencyShortcutAvailable: true)
    let pauseUntil = Date().addingTimeInterval(600)
    settings.pause(until: pauseUntil)
    let scheduler = ScareScheduler(settings: settings, activity: SystemActivityMonitor())

    XCTAssertEqual(scheduler.currentStatus(), .blocked(.paused(until: pauseUntil)))

    await scheduler.handleTimer()

    XCTAssertEqual(settings.values.activityEvents.first?.kind, .skipped)
    XCTAssertEqual(settings.values.activityEvents.first?.reason, .paused)
  }

  func testTriggerDecisionIncludesChanceMode() {
    var settings = allDaySettings()
    settings.mode = .randomChance
    let context = ScheduleContext(
      now: date(2026, 7, 14, 12, 0), lastScare: nil, scaresToday: 0)
    var rng = SeededRNG(seed: 9)

    settings.chancePercent = 0
    XCTAssertFalse(
      engine.shouldTrigger(
        context: context, settings: settings, using: &rng, calendar: calendar))

    settings.chancePercent = 100
    XCTAssertTrue(
      engine.shouldTrigger(
        context: context, settings: settings, using: &rng, calendar: calendar))
  }

  func testTriggerDecisionCombinesEligibilityAndMode() {
    var settings = allDaySettings()
    settings.mode = .fixedInterval
    let now = date(2026, 7, 14, 12, 0)
    var rng = SeededRNG(seed: 11)

    XCTAssertTrue(
      engine.shouldTrigger(
        context: .init(now: now, lastScare: nil, scaresToday: 0),
        settings: settings, using: &rng, calendar: calendar))
    XCTAssertFalse(
      engine.shouldTrigger(
        context: .init(now: now, lastScare: nil, scaresToday: 0, isSystemBlocked: true),
        settings: settings, using: &rng, calendar: calendar))
  }

  private func allDaySettings() -> ScheduleSettings {
    var settings = ScheduleSettings()
    settings.activeDays = Set(1...7)
    settings.activeStartMinutes = 0
    settings.activeEndMinutes = 0
    settings.cooldown = 0
    return settings
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    calendar.date(
      from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }
}

private struct SeededRNG: RandomNumberGenerator {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return state
  }
}
