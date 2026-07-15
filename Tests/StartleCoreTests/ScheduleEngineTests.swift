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

    func testRandomIntervalStaysWithinBounds() {
        var settings = allDaySettings()
        settings.mode = .randomInterval
        settings.minimumInterval = 600
        settings.maximumInterval = 1200
        let now = date(2026, 7, 14, 12, 0)
        var rng = SeededRNG(seed: 42)
        for _ in 0..<100 {
            let next = engine.nextTriggerDate(after: now, settings: settings, using: &rng, calendar: calendar)
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
        XCTAssertEqual(engine.nextTriggerDate(after: now, settings: settings, using: &rng, calendar: calendar), now.addingTimeInterval(3600))
    }

    func testCooldownBlocksUntilElapsed() {
        var settings = allDaySettings()
        settings.cooldown = 1800
        let now = date(2026, 7, 14, 12, 0)
        XCTAssertFalse(engine.isEligible(context: .init(now: now, lastScare: now.addingTimeInterval(-1799), scaresToday: 1), settings: settings, calendar: calendar))
        XCTAssertTrue(engine.isEligible(context: .init(now: now, lastScare: now.addingTimeInterval(-1800), scaresToday: 1), settings: settings, calendar: calendar))
    }

    func testActiveHoursAndDaysAreEnforced() {
        var settings = allDaySettings()
        settings.activeDays = [3]
        settings.activeStartMinutes = 9 * 60
        settings.activeEndMinutes = 22 * 60
        XCTAssertTrue(engine.isWithinActiveWindow(date(2026, 7, 14, 9, 0), settings: settings, calendar: calendar))
        XCTAssertTrue(engine.isWithinActiveWindow(date(2026, 7, 14, 21, 59), settings: settings, calendar: calendar))
        XCTAssertFalse(engine.isWithinActiveWindow(date(2026, 7, 14, 22, 0), settings: settings, calendar: calendar))
        XCTAssertFalse(engine.isWithinActiveWindow(date(2026, 7, 15, 12, 0), settings: settings, calendar: calendar))
    }

    func testOvernightActiveWindowCrossesMidnight() {
        var settings = allDaySettings()
        settings.activeStartMinutes = 22 * 60
        settings.activeEndMinutes = 6 * 60
        XCTAssertTrue(engine.isWithinActiveWindow(date(2026, 7, 14, 23, 0), settings: settings, calendar: calendar))
        XCTAssertTrue(engine.isWithinActiveWindow(date(2026, 7, 14, 5, 59), settings: settings, calendar: calendar))
        XCTAssertFalse(engine.isWithinActiveWindow(date(2026, 7, 14, 12, 0), settings: settings, calendar: calendar))
    }

    func testDailyLimitPreventsScare() {
        var settings = allDaySettings()
        settings.maximumScaresPerDay = 3
        XCTAssertFalse(engine.isEligible(context: .init(now: date(2026, 7, 14, 12, 0), lastScare: nil, scaresToday: 3), settings: settings, calendar: calendar))
    }

    func testSleepWakeRescheduleAlwaysCreatesNewFutureDate() {
        var settings = allDaySettings()
        settings.mode = .fixedInterval
        settings.fixedInterval = 900
        let wake = date(2026, 7, 14, 12, 0)
        var rng = SeededRNG(seed: 7)
        let replacement = engine.nextTriggerDate(after: wake, settings: settings, using: &rng, calendar: calendar)
        XCTAssertEqual(replacement, wake.addingTimeInterval(900))
        XCTAssertGreaterThan(replacement, wake)
    }

    func testPauseAndSystemBlockPreventScare() {
        let settings = allDaySettings()
        let now = date(2026, 7, 14, 12, 0)
        XCTAssertFalse(engine.isEligible(context: .init(now: now, lastScare: nil, scaresToday: 0, isSystemBlocked: true), settings: settings, calendar: calendar))
        XCTAssertFalse(engine.isEligible(context: .init(now: now, lastScare: nil, scaresToday: 0, pauseUntil: now.addingTimeInterval(60)), settings: settings, calendar: calendar))
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
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
