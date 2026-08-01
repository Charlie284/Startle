import AppKit
import Foundation
import Observation
import StartleCore
import UniformTypeIdentifiers

@MainActor @Observable
final class AppState {
  let settings: SettingsStore
  let library: VideoLibrary
  let activity: SystemActivityMonitor
  let scheduler: ScareScheduler
  let coordinator: ScareCoordinator
  let launchAtLogin: LaunchAtLoginManager
  let softwareUpdater: SoftwareUpdater
  private var emergencyShortcut: EmergencyShortcutManager!

  init() {
    let settings = SettingsStore()
    let library = VideoLibrary()
    let activity = SystemActivityMonitor()
    self.settings = settings
    self.library = library
    self.activity = activity
    scheduler = ScareScheduler(settings: settings, activity: activity)
    coordinator = ScareCoordinator(settings: settings, library: library)
    launchAtLogin = LaunchAtLoginManager()
    softwareUpdater = SoftwareUpdater()
    emergencyShortcut = EmergencyShortcutManager { [weak self] in self?.emergencyDisable() }
    scheduler.onTrigger = { [weak self] in await self?.coordinator.trigger() }
    library.onEnabledVideosChanged = { [weak self] hasVideos in
      guard let self, !hasVideos, self.settings.values.scaresEnabled else { return }
      self.setEnabled(false)
    }
    activity.onSuspend = { [weak coordinator] in coordinator?.dismiss() }
    activity.onWake = { [weak scheduler] in scheduler?.reschedule() }
    launchAtLogin.reconcile(forbidden: settings.values.safety.neverRunAtLogin)
    if settings.values.scaresEnabled
      && (!settings.values.onboardingCompleted || library.enabledVideos.isEmpty
        || !emergencyShortcut.isRegistered)
    {
      try? settings.setEnabled(false, hasVideos: false, emergencyShortcutAvailable: false)
    }
    scheduler.reschedule()
  }

  var combinedError: String? {
    settings.errorMessage
      ?? library.errorMessage
      ?? launchAtLogin.errorMessage
      ?? emergencyShortcut?.errorMessage
  }
  var emergencyShortcutIsRegistered: Bool { emergencyShortcut?.isRegistered == true }

  func currentStatus(at date: Date = Date(), calendar: Calendar = .current) -> SchedulerStatus {
    let status = scheduler.currentStatus(at: date, calendar: calendar)
    guard case .ready = status else { return status }
    if let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
      let application = settings.values.safety.excludedApplications.first(where: {
        $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
      })
    {
      return .blocked(.excludedApplication(application.displayName))
    }
    if let nextEligibleDate = library.nextVideoEligibilityDate(at: date) {
      return .blocked(.videoCooldown(until: nextEligibleDate))
    }
    return status
  }

  func clearError() {
    settings.clearError()
    library.clearError()
    launchAtLogin.clearError()
    emergencyShortcut?.clearError()
  }

  func setEnabled(_ enabled: Bool) {
    do {
      try settings.setEnabled(
        enabled,
        hasVideos: !library.enabledVideos.isEmpty,
        emergencyShortcutAvailable: emergencyShortcut.isRegistered
      )
      scheduler.reschedule()
    } catch { settings.present(error) }
  }

  func retryEmergencyShortcut() { emergencyShortcut.register() }

  func scheduleChanged() { scheduler.reschedule() }

  func pause(for interval: TimeInterval) {
    settings.pause(for: interval)
    scheduler.reschedule()
  }

  func pauseUntilTomorrow(now: Date = Date(), calendar: Calendar = .current) {
    guard
      let tomorrow = calendar.date(
        byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
    else { return }
    settings.pause(until: tomorrow)
    scheduler.reschedule()
  }

  func pauseUntilNextActiveWindow(now: Date = Date(), calendar: Calendar = .current) {
    guard let nextWindow = scheduler.nextActiveWindowStart(after: now, calendar: calendar) else {
      settings.present(StartleError.noActiveDays)
      return
    }
    settings.pause(until: nextWindow)
    scheduler.reschedule()
  }

  func resumeNow() {
    settings.resume()
    scheduler.reschedule()
  }

  func emergencyDisable() {
    coordinator.dismiss()
    setEnabled(false)
  }

  func testScare(video: VideoItem? = nil) {
    Task { await coordinator.trigger(isTest: true, specificVideo: video) }
  }

  func chooseVideos() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
    panel.message = "Choose one or more videos for Startle"
    guard panel.runModal() == .OK else { return }
    importVideos(panel.urls)
  }

  func chooseExcludedApplication() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [.applicationBundle]
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    panel.message = "Choose an app where Startle must never fire"
    panel.prompt = "Exclude App"
    guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
      let bundleIdentifier = bundle.bundleIdentifier
    else { return }
    let displayName =
      bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? url.deletingPathExtension().lastPathComponent
    settings.excludeApplication(
      ExcludedApplication(bundleIdentifier: bundleIdentifier, displayName: displayName))
  }

  func removeExcludedApplication(_ application: ExcludedApplication) {
    settings.removeExcludedApplication(application)
  }

  func chooseReplacement(for item: VideoItem) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
    panel.message = "Locate a replacement for \(item.displayName)"
    let previousFolder = URL(fileURLWithPath: item.lastKnownPath).deletingLastPathComponent()
    if FileManager.default.fileExists(atPath: previousFolder.path) {
      panel.directoryURL = previousFolder
    }
    guard panel.runModal() == .OK, let url = panel.url else { return }
    Task {
      if await library.relink(item, to: url) {
        scheduler.reschedule()
      }
    }
  }

  func importVideos(_ urls: [URL]) {
    Task { await importVideosNow(urls) }
  }

  func importVideosNow(_ urls: [URL]) async {
    _ = await library.importVideos(from: urls)
    if settings.values.scaresEnabled && library.enabledVideos.isEmpty { setEnabled(false) }
    scheduler.reschedule()
  }

  func removeVideo(_ item: VideoItem) {
    library.remove(item)
    if library.enabledVideos.isEmpty { setEnabled(false) }
  }

  func setAllVideosEnabled(_ enabled: Bool) {
    library.setAllEnabled(enabled)
    if library.enabledVideos.isEmpty { setEnabled(false) }
  }

  @discardableResult
  func removeMissingVideos() -> Int {
    let removed = library.removeMissingVideos()
    if library.enabledVideos.isEmpty { setEnabled(false) }
    return removed
  }
}
