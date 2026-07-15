import Foundation
import Observation
import os

@MainActor @Observable
public final class SettingsStore {
    public var values: PersistedSettings { didSet { persist() } }
    public private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let key = "Startle.Settings.v1"
    private let logger = Logger(subsystem: "com.startle.app", category: "settings")

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
            values = decoded
        } else {
            values = PersistedSettings()
        }
        pruneDailyHistory()
    }

    public func setEnabled(_ enabled: Bool, hasVideos: Bool) throws {
        guard !enabled || values.onboardingCompleted else { throw StartleError.onboardingRequired }
        guard !enabled || hasVideos else { throw StartleError.noVideos }
        values.scaresEnabled = enabled
        if !enabled { values.pauseUntil = nil }
    }

    public func pause(for interval: TimeInterval) {
        values.pauseUntil = Date().addingTimeInterval(interval)
    }

    public func recordScare(at date: Date = Date()) {
        values.totalScareCount += 1
        values.lastScareDate = date
        values.dailyScareDates.append(date)
        pruneDailyHistory(now: date)
    }

    public func scaresToday(now: Date = Date(), calendar: Calendar = .current) -> Int {
        values.dailyScareDates.filter { calendar.isDate($0, inSameDayAs: now) }.count
    }

    public func present(_ error: Error) { errorMessage = error.localizedDescription }
    public func clearError() { errorMessage = nil }

    private func pruneDailyHistory(now: Date = Date()) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -8, to: now) ?? now
        values.dailyScareDates.removeAll { $0 < cutoff }
    }

    private func persist() {
        do { defaults.set(try JSONEncoder().encode(values), forKey: key) }
        catch { logger.error("Could not persist settings: \(error.localizedDescription, privacy: .public)") }
    }
}
