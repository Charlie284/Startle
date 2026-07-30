import Foundation
import Observation
import os

@MainActor @Observable
public final class ScareScheduler {
  public private(set) var nextTriggerDate: Date?
  public var onTrigger: (@MainActor () async -> Void)?

  private let settings: SettingsStore
  private let activity: SystemActivityMonitor
  private let engine = ScheduleEngine()
  @ObservationIgnored nonisolated(unsafe) private var task: Task<Void, Never>?
  private let logger = Logger(subsystem: "com.startle.app", category: "scheduler")

  public init(settings: SettingsStore, activity: SystemActivityMonitor) {
    self.settings = settings
    self.activity = activity
  }

  deinit { task?.cancel() }

  public func reschedule() {
    reschedule(after: Date())
  }

  func reschedule(after now: Date) {
    task?.cancel()
    task = nil
    nextTriggerDate = nil
    guard settings.values.scaresEnabled else { return }
    var rng = SystemRandomNumberGenerator()
    guard
      let date = engine.nextTriggerDate(
        after: now, settings: settings.values.schedule, using: &rng)
    else { return }
    nextTriggerDate = date
    logger.info("Next scheduling check at \(date, privacy: .public)")
    task = Task { [weak self] in
      let wait = max(0, date.timeIntervalSinceNow)
      do { try await Task.sleep(for: .seconds(wait)) } catch { return }
      guard !Task.isCancelled else { return }
      await self?.handleTimer()
    }
  }

  public var nextWindowDescription: String {
    guard settings.values.scaresEnabled else { return "Scares are disabled" }
    guard !settings.values.schedule.activeDays.isEmpty else { return "No active days selected" }
    guard let nextTriggerDate else { return "Scheduling…" }
    return "Around " + nextTriggerDate.formatted(date: .omitted, time: .shortened)
  }

  func handleTimer() async {
    defer { reschedule() }
    guard settings.values.scaresEnabled else { return }
    let schedule = settings.values.schedule
    let context = ScheduleContext(
      now: Date(), lastScare: settings.values.lastScareDate,
      scaresToday: settings.scaresToday(),
      isSystemBlocked: activity.blocked(by: settings.values.safety, schedule: schedule),
      pauseUntil: settings.values.pauseUntil
    )
    var rng = SystemRandomNumberGenerator()
    guard engine.shouldTrigger(context: context, settings: schedule, using: &rng) else { return }
    await onTrigger?()
  }
}
