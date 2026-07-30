import Foundation
import XCTest

@testable import StartleCore

final class SafetyPolicyTests: XCTestCase {
  private let policy = SafetyPolicy()
  private let now = Date(timeIntervalSince1970: 1_000_000)

  func testSleepAndLockAlwaysBlock() {
    let activity = SystemActivitySnapshot(isAsleepOrLocked: true)

    XCTAssertEqual(reason(for: activity), .asleepOrLocked)
  }

  func testOptionalActivitySignalsRespectTheirSettings() {
    var safety = SafetySettings()
    safety.pauseForScreenCapture = false
    safety.pauseForFullScreenApps = false
    safety.pauseForCameraOrMicrophone = false
    safety.disableWithExternalDisplay = false
    let activity = SystemActivitySnapshot(
      isScreenCaptured: true,
      isFullScreenAppActive: true,
      hasExternalDisplay: true,
      cameraOrMicrophoneDetected: true
    )

    XCTAssertNil(reason(for: activity, safety: safety))

    safety.pauseForScreenCapture = true
    XCTAssertEqual(reason(for: activity, safety: safety), .screenCapture)
    safety.pauseForScreenCapture = false
    safety.pauseForFullScreenApps = true
    XCTAssertEqual(reason(for: activity, safety: safety), .fullScreenApp)
    safety.pauseForFullScreenApps = false
    safety.pauseForCameraOrMicrophone = true
    XCTAssertEqual(reason(for: activity, safety: safety), .cameraOrMicrophone)
    safety.pauseForCameraOrMicrophone = false
    safety.disableWithExternalDisplay = true
    XCTAssertEqual(reason(for: activity, safety: safety), .externalDisplay)
  }

  func testBatteryAndVolumeUseStrictThresholds() {
    var safety = SafetySettings()
    safety.disableBelowBatteryPercent = 20
    safety.disableAboveSystemVolumePercent = 80

    XCTAssertNil(
      reason(
        for: SystemActivitySnapshot(batteryPercent: 20, systemVolumePercent: 80), safety: safety)
    )
    XCTAssertEqual(
      reason(for: SystemActivitySnapshot(batteryPercent: 19.9), safety: safety), .lowBattery)
    XCTAssertEqual(
      reason(for: SystemActivitySnapshot(systemVolumePercent: 80.1), safety: safety), .highVolume)
  }

  func testIdleGracePeriodExpiresAtBoundary() {
    var schedule = ScheduleSettings()
    schedule.avoidAfterIdle = true
    schedule.idleGracePeriod = 300

    XCTAssertEqual(
      reason(
        for: SystemActivitySnapshot(idleReturnDate: now.addingTimeInterval(-299)),
        schedule: schedule),
      .idleReturnGracePeriod)
    XCTAssertNil(
      reason(
        for: SystemActivitySnapshot(idleReturnDate: now.addingTimeInterval(-300)),
        schedule: schedule)
    )
  }

  private func reason(
    for activity: SystemActivitySnapshot,
    safety: SafetySettings = SafetySettings(),
    schedule: ScheduleSettings = ScheduleSettings()
  ) -> SafetyBlockReason? {
    policy.blockReason(for: activity, safety: safety, schedule: schedule, now: now)
  }
}

@MainActor
final class SystemActivityMonitorTests: XCTestCase {
  func testSuspensionPublishesCallbackAndWakeClearsBlock() {
    let monitor = SystemActivityMonitor()
    var suspensionCount = 0
    var wakeCount = 0
    monitor.onSuspend = { suspensionCount += 1 }
    monitor.onWake = { wakeCount += 1 }

    monitor.handleSuspension()

    XCTAssertTrue(monitor.isAsleepOrLocked)
    XCTAssertEqual(suspensionCount, 1)

    monitor.handleWake()

    XCTAssertFalse(monitor.isAsleepOrLocked)
    XCTAssertNotNil(monitor.lastWakeDate)
    XCTAssertEqual(wakeCount, 1)
  }

  func testFullScreenMatchRequiresDisplayOriginAndSize() {
    let displays = [
      CGRect(x: 0, y: 0, width: 1920, height: 1080),
      CGRect(x: 1920, y: 0, width: 1920, height: 1080),
    ]

    XCTAssertTrue(
      SystemActivityMonitor.boundsMatchDisplay(
        CGRect(x: 1920, y: 0, width: 1920, height: 1080), displayBounds: displays))
    XCTAssertFalse(
      SystemActivityMonitor.boundsMatchDisplay(
        CGRect(x: 960, y: 0, width: 1920, height: 1080), displayBounds: displays))
  }
}

@MainActor
final class ScareWindowControllerTests: XCTestCase {
  func testPresentationWatchdogIncludesCountdownAndTrimmedDuration() {
    let video = VideoItem(
      displayName: "Trimmed", bookmarkData: Data(), duration: 10,
      trimStart: 2, trimEnd: 5, lastKnownPath: "/tmp/Trimmed.mov")

    XCTAssertEqual(
      ScareWindowController.presentationWatchdogInterval(video: video, countdownSeconds: 4),
      37)
  }

  func testDismissIsSafeWithoutAnActivePresentation() {
    let controller = ScareWindowController()

    controller.dismiss()

    XCTAssertFalse(controller.isPresenting)
  }
}
