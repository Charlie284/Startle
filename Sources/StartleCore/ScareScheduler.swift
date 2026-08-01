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

  public func currentStatus(
    at now: Date = Date(), calendar: Calendar = .current
  ) -> SchedulerStatus {
    guard settings.values.scaresEnabled else { return .disabled }
    let schedule = settings.values.schedule
    if let pauseUntil = settings.values.pauseUntil, pauseUntil > now {
      return .blocked(.paused(until: pauseUntil))
    }
    if let reason = activity.blockReason(
      by: settings.values.safety, schedule: schedule, now: now)
    {
      return .blocked(.safety(reason))
    }
    guard engine.isWithinActiveWindow(now, settings: schedule, calendar: calendar) else {
      return .blocked(.outsideActiveWindow)
    }
    guard settings.scaresToday(now: now, calendar: calendar) < schedule.maximumScaresPerDay else {
      return .blocked(.dailyLimit)
    }
    if let lastScareDate = settings.values.lastScareDate {
      let cooldownEnd = lastScareDate.addingTimeInterval(schedule.cooldown)
      if cooldownEnd > now { return .blocked(.cooldown(until: cooldownEnd)) }
    }
    return .ready(nextTrigger: nextTriggerDate)
  }

  public func nextActiveWindowStart(
    after now: Date = Date(), calendar: Calendar = .current
  ) -> Date? {
    engine.nextActiveWindowStart(after: now, settings: settings.values.schedule, calendar: calendar)
  }

  func handleTimer() async {
    defer { reschedule() }
    guard settings.values.scaresEnabled else { return }
    let schedule = settings.values.schedule
    let now = Date()
    if case .blocked(let reason) = currentStatus(at: now) {
      settings.recordActivity(
        ActivityEvent(
          occurredAt: now, kind: .skipped, reason: reason.activityEventReason))
      return
    }
    let context = ScheduleContext(
      now: now, lastScare: settings.values.lastScareDate,
      scaresToday: settings.scaresToday(),
      isSystemBlocked: false,
      pauseUntil: settings.values.pauseUntil
    )
    var rng = SystemRandomNumberGenerator()
    guard engine.shouldTrigger(context: context, settings: schedule, using: &rng) else {
      settings.recordActivity(
        ActivityEvent(occurredAt: now, kind: .skipped, reason: .chanceNotSelected))
      return
    }
    await onTrigger?()
  }
}

extension ScheduleBlockReason {
  fileprivate var activityEventReason: ActivityEventReason {
    switch self {
    case .paused: .paused
    case .outsideActiveWindow: .outsideActiveWindow
    case .dailyLimit: .dailyLimit
    case .cooldown: .cooldown
    case .excludedApplication: .excludedApplication
    case .videoCooldown: .noEligibleVideo
    case .safety(let reason): reason.activityEventReason
    }
  }
}

extension SafetyBlockReason {
  fileprivate var activityEventReason: ActivityEventReason {
    switch self {
    case .asleepOrLocked: .asleepOrLocked
    case .screenCapture: .screenCapture
    case .fullScreenApp: .fullScreenApp
    case .cameraOrMicrophone: .cameraOrMicrophone
    case .externalDisplay: .externalDisplay
    case .lowBattery: .lowBattery
    case .highVolume: .highVolume
    case .idleReturnGracePeriod: .idleReturnGracePeriod
    }
  }
}
