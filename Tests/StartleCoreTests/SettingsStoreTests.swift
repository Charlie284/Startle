import Foundation
import Observation
import ServiceManagement
import XCTest

@testable import StartleCore

@MainActor
final class SettingsStoreTests: XCTestCase {
  func testOlderSettingsPayloadUsesCurrentDefaultsForMissingFields() throws {
    let data = Data(
      #"{"scaresEnabled":true,"onboardingCompleted":true,"schedule":{"mode":"fixedInterval","fixedInterval":900},"appearance":{"menuBarIcon":"ghost"}}"#
        .utf8)

    let settings = try JSONDecoder().decode(PersistedSettings.self, from: data)

    XCTAssertTrue(settings.scaresEnabled)
    XCTAssertTrue(settings.onboardingCompleted)
    XCTAssertEqual(settings.schedule.mode, .fixedInterval)
    XCTAssertEqual(settings.schedule.fixedInterval, 900)
    XCTAssertEqual(settings.schedule.maximumScaresPerDay, 5)
    XCTAssertTrue(settings.safety.neverRunAtLogin)
    XCTAssertFalse(settings.safety.pauseForFocus)
    XCTAssertTrue(settings.safety.excludedApplications.isEmpty)
    XCTAssertEqual(settings.appearance.displayMode, .fullScreen)
    XCTAssertTrue(settings.activityEvents.isEmpty)
  }

  func testPersistedSettingsRoundTrip() throws {
    var original = PersistedSettings()
    original.onboardingCompleted = true
    original.schedule.activeDays = [2, 4, 6]
    original.safety.quietMode = true
    original.safety.excludedApplications = [
      ExcludedApplication(bundleIdentifier: "us.zoom.xos", displayName: "zoom.us")
    ]
    original.appearance.cropToFill = true
    original.activityEvents = [
      ActivityEvent(
        occurredAt: Date(timeIntervalSince1970: 123), kind: .skipped,
        reason: .cameraOrMicrophone)
    ]

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(PersistedSettings.self, from: data)

    XCTAssertEqual(decoded, original)
  }

  func testActivityHistoryKeepsNewestFiftyEventsAndCanBeCleared() {
    let suiteName = "StartleCoreTests.SettingsStore.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SettingsStore(defaults: defaults)

    for index in 0..<55 {
      store.recordActivity(
        ActivityEvent(
          occurredAt: Date(timeIntervalSince1970: TimeInterval(index)), kind: .skipped,
          reason: .chanceNotSelected))
    }

    XCTAssertEqual(store.values.activityEvents.count, 50)
    XCTAssertEqual(store.values.activityEvents.first?.occurredAt, Date(timeIntervalSince1970: 54))
    XCTAssertEqual(store.values.activityEvents.last?.occurredAt, Date(timeIntervalSince1970: 5))

    let reloaded = SettingsStore(defaults: defaults)
    XCTAssertEqual(reloaded.values.activityEvents, store.values.activityEvents)

    store.clearActivityHistory()
    XCTAssertTrue(store.values.activityEvents.isEmpty)
  }

  func testPauseUntilAndResumeUpdatePersistedPause() {
    let suiteName = "StartleCoreTests.SettingsStore.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SettingsStore(defaults: defaults)
    let date = Date(timeIntervalSince1970: 1_234)

    store.pause(until: date)
    XCTAssertEqual(store.values.pauseUntil, date)

    store.resume()
    XCTAssertNil(store.values.pauseUntil)
  }

  func testPauseForFourHoursUsesDurationFromNow() throws {
    let suiteName = "StartleCoreTests.SettingsStore.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SettingsStore(defaults: defaults)
    let beforePause = Date()

    store.pause(for: 4 * 60 * 60)

    let pauseUntil = try XCTUnwrap(store.values.pauseUntil)
    XCTAssertGreaterThanOrEqual(pauseUntil, beforePause.addingTimeInterval(4 * 60 * 60))
    XCTAssertLessThan(pauseUntil, Date().addingTimeInterval(4 * 60 * 60 + 1))
  }

  func testExcludedApplicationsMatchBundleIdentifiersCaseInsensitively() {
    var safety = SafetySettings()
    safety.excludedApplications = [
      ExcludedApplication(bundleIdentifier: "com.apple.Keynote", displayName: "Keynote")
    ]

    XCTAssertTrue(safety.excludesApplication(bundleIdentifier: "com.apple.keynote"))
    XCTAssertFalse(safety.excludesApplication(bundleIdentifier: "com.apple.FinalCut"))
    XCTAssertFalse(safety.excludesApplication(bundleIdentifier: nil))
  }

  func testExcludedApplicationMutationsAvoidDuplicates() {
    let suiteName = "StartleCoreTests.SettingsStore.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SettingsStore(defaults: defaults)
    let application = ExcludedApplication(
      bundleIdentifier: "com.obsproject.obs-studio", displayName: "OBS")

    store.excludeApplication(application)
    store.excludeApplication(
      ExcludedApplication(bundleIdentifier: "COM.OBSPROJECT.OBS-STUDIO", displayName: "OBS Copy"))

    XCTAssertEqual(store.values.safety.excludedApplications, [application])

    store.removeExcludedApplication(application)

    XCTAssertTrue(store.values.safety.excludedApplications.isEmpty)
  }

  func testCorruptSettingsAreBackedUpBeforeReset() {
    let suiteName = "StartleCoreTests.SettingsStore.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let invalidData = Data("not-json".utf8)
    defaults.set(invalidData, forKey: "Startle.Settings.v1")

    let store = SettingsStore(defaults: defaults)

    XCTAssertNotNil(store.errorMessage)
    XCTAssertEqual(defaults.data(forKey: "Startle.Settings.v1.recovery"), invalidData)
    XCTAssertNotEqual(defaults.data(forKey: "Startle.Settings.v1"), invalidData)
    XCTAssertEqual(store.values, PersistedSettings())
  }

  func testEnablingRequiresEmergencyShortcut() throws {
    let suiteName = "StartleCoreTests.SettingsStore.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SettingsStore(defaults: defaults)
    store.values.onboardingCompleted = true

    XCTAssertThrowsError(
      try store.setEnabled(true, hasVideos: true, emergencyShortcutAvailable: false)
    ) { error in
      XCTAssertEqual(
        error.localizedDescription, StartleError.emergencyShortcutUnavailable.localizedDescription)
    }
    XCTAssertFalse(store.values.scaresEnabled)

    try store.setEnabled(true, hasVideos: true, emergencyShortcutAvailable: true)
    XCTAssertTrue(store.values.scaresEnabled)

    try store.setEnabled(false, hasVideos: false, emergencyShortcutAvailable: false)
    XCTAssertFalse(store.values.scaresEnabled)
  }

  func testNeverRunAtLoginReconciliationUnregistersExistingService() {
    let service = FakeLaunchAtLoginService(status: .enabled)
    let manager = LaunchAtLoginManager(service: service)

    manager.reconcile(forbidden: true)

    XCTAssertEqual(service.unregisterCount, 1)
    XCTAssertFalse(manager.isEnabled)
    XCTAssertNil(manager.errorMessage)
  }

  func testLaunchAtLoginReconciliationDoesNothingWhenAllowed() {
    let service = FakeLaunchAtLoginService(status: .enabled)
    let manager = LaunchAtLoginManager(service: service)

    manager.reconcile(forbidden: false)

    XCTAssertEqual(service.unregisterCount, 0)
    XCTAssertTrue(manager.isEnabled)
  }

  func testEmergencyShortcutRetryUpdatesObservedRegistrationState() {
    var attemptCount = 0
    let manager = EmergencyShortcutManager(
      action: {},
      registrationAttempt: {
        attemptCount += 1
        return attemptCount == 1 ? "Shortcut conflict" : nil
      })
    XCTAssertFalse(manager.isRegistered)
    XCTAssertEqual(manager.errorMessage, "Shortcut conflict")
    let observationCount = LockedCounter()
    withObservationTracking {
      _ = manager.isRegistered
      _ = manager.errorMessage
    } onChange: {
      observationCount.increment()
    }

    manager.register()

    XCTAssertTrue(manager.isRegistered)
    XCTAssertNil(manager.errorMessage)
    XCTAssertEqual(observationCount.value, 1)
  }
}

private final class LockedCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  func increment() {
    lock.lock()
    count += 1
    lock.unlock()
  }
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginService {
  var status: SMAppService.Status
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0

  init(status: SMAppService.Status) {
    self.status = status
  }

  func register() throws {
    registerCount += 1
    status = .enabled
  }

  func unregister() throws {
    unregisterCount += 1
    status = .notRegistered
  }
}
