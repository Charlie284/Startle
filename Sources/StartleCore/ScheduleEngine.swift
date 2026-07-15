import Foundation

public struct ScheduleContext: Sendable {
    public var now: Date
    public var lastScare: Date?
    public var scaresToday: Int
    public var isSystemBlocked: Bool
    public var pauseUntil: Date?

    public init(now: Date, lastScare: Date?, scaresToday: Int, isSystemBlocked: Bool = false, pauseUntil: Date? = nil) {
        self.now = now; self.lastScare = lastScare; self.scaresToday = scaresToday
        self.isSystemBlocked = isSystemBlocked; self.pauseUntil = pauseUntil
    }
}

public struct ScheduleEngine: Sendable {
    public init() {}

    public func isWithinActiveWindow(_ date: Date, settings: ScheduleSettings, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        guard settings.activeDays.contains(weekday) else { return false }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if settings.activeStartMinutes == settings.activeEndMinutes { return true }
        if settings.activeStartMinutes < settings.activeEndMinutes {
            return minute >= settings.activeStartMinutes && minute < settings.activeEndMinutes
        }
        return minute >= settings.activeStartMinutes || minute < settings.activeEndMinutes
    }

    public func isEligible(context: ScheduleContext, settings: ScheduleSettings, calendar: Calendar = .current) -> Bool {
        guard !context.isSystemBlocked, isWithinActiveWindow(context.now, settings: settings, calendar: calendar) else { return false }
        guard context.scaresToday < settings.maximumScaresPerDay else { return false }
        if let pause = context.pauseUntil, pause > context.now { return false }
        if let last = context.lastScare, context.now.timeIntervalSince(last) < settings.cooldown { return false }
        return true
    }

    public func nextTriggerDate<R: RandomNumberGenerator>(
        after now: Date, settings: ScheduleSettings, using rng: inout R, calendar: Calendar = .current
    ) -> Date {
        let interval: TimeInterval
        switch settings.mode {
        case .randomInterval:
            interval = Double.random(in: min(settings.minimumInterval, settings.maximumInterval)...max(settings.minimumInterval, settings.maximumInterval), using: &rng)
        case .fixedInterval:
            interval = max(60, settings.fixedInterval)
        case .randomChance:
            interval = max(60, settings.chanceCheckInterval)
        }
        return advanceToActiveWindow(now.addingTimeInterval(max(60, interval)), settings: settings, calendar: calendar)
    }

    public func shouldFireChance<R: RandomNumberGenerator>(settings: ScheduleSettings, using rng: inout R) -> Bool {
        Double.random(in: 0..<100, using: &rng) < min(100, max(0, settings.chancePercent))
    }

    private func advanceToActiveWindow(_ candidate: Date, settings: ScheduleSettings, calendar: Calendar) -> Date {
        guard !isWithinActiveWindow(candidate, settings: settings, calendar: calendar) else { return candidate }
        var cursor = candidate
        for _ in 0..<(8 * 24 * 60) {
            cursor = cursor.addingTimeInterval(60)
            if isWithinActiveWindow(cursor, settings: settings, calendar: calendar) { return cursor }
        }
        return candidate.addingTimeInterval(24 * 60 * 60)
    }
}
