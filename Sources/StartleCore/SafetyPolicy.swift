import Foundation

public enum SafetyBlockReason: Equatable, Sendable {
  case asleepOrLocked
  case screenCapture
  case fullScreenApp
  case cameraOrMicrophone
  case externalDisplay
  case lowBattery
  case highVolume
  case idleReturnGracePeriod
}

public struct SystemActivitySnapshot: Equatable, Sendable {
  public var isAsleepOrLocked: Bool
  public var isScreenCaptured: Bool
  public var isFullScreenAppActive: Bool
  public var hasExternalDisplay: Bool
  public var batteryPercent: Double
  public var systemVolumePercent: Double
  public var cameraOrMicrophoneDetected: Bool
  public var idleReturnDate: Date?

  public init(
    isAsleepOrLocked: Bool = false,
    isScreenCaptured: Bool = false,
    isFullScreenAppActive: Bool = false,
    hasExternalDisplay: Bool = false,
    batteryPercent: Double = 100,
    systemVolumePercent: Double = 0,
    cameraOrMicrophoneDetected: Bool = false,
    idleReturnDate: Date? = nil
  ) {
    self.isAsleepOrLocked = isAsleepOrLocked
    self.isScreenCaptured = isScreenCaptured
    self.isFullScreenAppActive = isFullScreenAppActive
    self.hasExternalDisplay = hasExternalDisplay
    self.batteryPercent = batteryPercent
    self.systemVolumePercent = systemVolumePercent
    self.cameraOrMicrophoneDetected = cameraOrMicrophoneDetected
    self.idleReturnDate = idleReturnDate
  }
}

public struct SafetyPolicy: Sendable {
  public init() {}

  public func blockReason(
    for activity: SystemActivitySnapshot,
    safety: SafetySettings,
    schedule: ScheduleSettings,
    now: Date
  ) -> SafetyBlockReason? {
    if activity.isAsleepOrLocked { return .asleepOrLocked }
    if safety.pauseForScreenCapture && activity.isScreenCaptured { return .screenCapture }
    if safety.pauseForFullScreenApps && activity.isFullScreenAppActive { return .fullScreenApp }
    if safety.pauseForCameraOrMicrophone && activity.cameraOrMicrophoneDetected {
      return .cameraOrMicrophone
    }
    if safety.disableWithExternalDisplay && activity.hasExternalDisplay { return .externalDisplay }
    if activity.batteryPercent < safety.disableBelowBatteryPercent { return .lowBattery }
    if activity.systemVolumePercent > safety.disableAboveSystemVolumePercent { return .highVolume }
    if schedule.avoidAfterIdle,
      let idleReturnDate = activity.idleReturnDate,
      now.timeIntervalSince(idleReturnDate) < schedule.idleGracePeriod
    {
      return .idleReturnGracePeriod
    }
    return nil
  }
}
