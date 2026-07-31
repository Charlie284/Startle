import Foundation

public enum ScheduleMode: String, Codable, CaseIterable, Sendable {
  case randomInterval, fixedInterval, randomChance

  public var title: String {
    switch self {
    case .randomInterval: "Random interval"
    case .fixedInterval: "Fixed interval"
    case .randomChance: "Random chance"
    }
  }
}

public enum AppTheme: String, Codable, CaseIterable, Sendable {
  case system, light, dark
  public var title: String { rawValue.capitalized }
}

public enum ScareDisplayMode: String, Codable, CaseIterable, Sendable {
  case fullScreen, centered, currentDisplay, allDisplays
  public var title: String {
    switch self {
    case .fullScreen: "Full screen"
    case .centered: "Centered borderless window"
    case .currentDisplay: "Current display only"
    case .allDisplays: "All displays"
    }
  }
}

public enum VideoSelectionMode: String, Codable, CaseIterable, Sendable {
  case weightedRandom, shuffleBag

  public var title: String {
    switch self {
    case .weightedRandom: "Weighted random"
    case .shuffleBag: "Shuffle bag"
    }
  }
}

public struct VideoSelectionSettings: Codable, Equatable, Sendable {
  public var mode: VideoSelectionMode = .weightedRandom
  public var recentHistoryCount = 4

  public init() {}

  public init(mode: VideoSelectionMode, recentHistoryCount: Int = 4) {
    self.mode = mode
    self.recentHistoryCount = min(5, max(3, recentHistoryCount))
  }

  public init(from decoder: Decoder) throws {
    self.init()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mode = try container.decodeIfPresent(VideoSelectionMode.self, forKey: .mode) ?? mode
    recentHistoryCount =
      try container.decodeIfPresent(Int.self, forKey: .recentHistoryCount) ?? recentHistoryCount
    recentHistoryCount = min(5, max(3, recentHistoryCount))
  }
}

public struct ExcludedApplication: Codable, Equatable, Hashable, Identifiable, Sendable {
  public var bundleIdentifier: String
  public var displayName: String

  public var id: String { bundleIdentifier }

  public init(bundleIdentifier: String, displayName: String) {
    self.bundleIdentifier = bundleIdentifier
    self.displayName = displayName
  }
}

public struct ScheduleSettings: Codable, Equatable, Sendable {
  public var mode: ScheduleMode = .randomInterval
  public var minimumInterval: TimeInterval = 30 * 60
  public var maximumInterval: TimeInterval = 90 * 60
  public var fixedInterval: TimeInterval = 60 * 60
  public var chanceCheckInterval: TimeInterval = 5 * 60
  public var chancePercent: Double = 15
  public var activeDays: Set<Int> = Set(1...7)
  public var activeStartMinutes: Int = 9 * 60
  public var activeEndMinutes: Int = 22 * 60
  public var cooldown: TimeInterval = 30 * 60
  public var maximumScaresPerDay: Int = 5
  public var avoidAfterIdle: Bool = true
  public var idleGracePeriod: TimeInterval = 5 * 60

  public init() {}

  public init(from decoder: Decoder) throws {
    self.init()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mode = try container.decodeIfPresent(ScheduleMode.self, forKey: .mode) ?? mode
    minimumInterval =
      try container.decodeIfPresent(TimeInterval.self, forKey: .minimumInterval) ?? minimumInterval
    maximumInterval =
      try container.decodeIfPresent(TimeInterval.self, forKey: .maximumInterval) ?? maximumInterval
    fixedInterval =
      try container.decodeIfPresent(TimeInterval.self, forKey: .fixedInterval) ?? fixedInterval
    chanceCheckInterval =
      try container.decodeIfPresent(TimeInterval.self, forKey: .chanceCheckInterval)
      ?? chanceCheckInterval
    chancePercent =
      try container.decodeIfPresent(Double.self, forKey: .chancePercent) ?? chancePercent
    activeDays = try container.decodeIfPresent(Set<Int>.self, forKey: .activeDays) ?? activeDays
    activeStartMinutes =
      try container.decodeIfPresent(Int.self, forKey: .activeStartMinutes) ?? activeStartMinutes
    activeEndMinutes =
      try container.decodeIfPresent(Int.self, forKey: .activeEndMinutes) ?? activeEndMinutes
    cooldown = try container.decodeIfPresent(TimeInterval.self, forKey: .cooldown) ?? cooldown
    maximumScaresPerDay =
      try container.decodeIfPresent(Int.self, forKey: .maximumScaresPerDay) ?? maximumScaresPerDay
    avoidAfterIdle =
      try container.decodeIfPresent(Bool.self, forKey: .avoidAfterIdle) ?? avoidAfterIdle
    idleGracePeriod =
      try container.decodeIfPresent(TimeInterval.self, forKey: .idleGracePeriod) ?? idleGracePeriod
  }
}

public struct SafetySettings: Codable, Equatable, Sendable {
  public var pauseForCameraOrMicrophone = true
  public var pauseForScreenCapture = true
  public var pauseForFullScreenApps = true
  // Retained for settings-file compatibility. macOS has no public Focus-state API.
  public var pauseForFocus = false
  public var disableWithExternalDisplay = false
  public var disableBelowBatteryPercent = 15.0
  public var disableAboveSystemVolumePercent = 85.0
  public var quietMode = false
  public var countdownSeconds = 0
  public var neverRunAtLogin = true
  public var excludedApplications: [ExcludedApplication] = []

  public init() {}

  public init(from decoder: Decoder) throws {
    self.init()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    pauseForCameraOrMicrophone =
      try container.decodeIfPresent(Bool.self, forKey: .pauseForCameraOrMicrophone)
      ?? pauseForCameraOrMicrophone
    pauseForScreenCapture =
      try container.decodeIfPresent(Bool.self, forKey: .pauseForScreenCapture)
      ?? pauseForScreenCapture
    pauseForFullScreenApps =
      try container.decodeIfPresent(Bool.self, forKey: .pauseForFullScreenApps)
      ?? pauseForFullScreenApps
    pauseForFocus = false
    disableWithExternalDisplay =
      try container.decodeIfPresent(Bool.self, forKey: .disableWithExternalDisplay)
      ?? disableWithExternalDisplay
    disableBelowBatteryPercent =
      try container.decodeIfPresent(Double.self, forKey: .disableBelowBatteryPercent)
      ?? disableBelowBatteryPercent
    disableAboveSystemVolumePercent =
      try container.decodeIfPresent(Double.self, forKey: .disableAboveSystemVolumePercent)
      ?? disableAboveSystemVolumePercent
    quietMode = try container.decodeIfPresent(Bool.self, forKey: .quietMode) ?? quietMode
    countdownSeconds =
      try container.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? countdownSeconds
    neverRunAtLogin =
      try container.decodeIfPresent(Bool.self, forKey: .neverRunAtLogin) ?? neverRunAtLogin
    excludedApplications =
      try container.decodeIfPresent([ExcludedApplication].self, forKey: .excludedApplications)
      ?? excludedApplications
  }

  public func excludesApplication(bundleIdentifier: String?) -> Bool {
    guard let bundleIdentifier else { return false }
    return excludedApplications.contains {
      $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
    }
  }
}

public struct AppearanceSettings: Codable, Equatable, Sendable {
  public var theme: AppTheme = .system
  public var displayMode: ScareDisplayMode = .fullScreen
  public var backgroundHex = "09090B"
  public var hideCursor = true
  public var cropToFill = false

  public init() {}

  public init(from decoder: Decoder) throws {
    self.init()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? theme
    displayMode =
      try container.decodeIfPresent(ScareDisplayMode.self, forKey: .displayMode) ?? displayMode
    backgroundHex =
      try container.decodeIfPresent(String.self, forKey: .backgroundHex) ?? backgroundHex
    hideCursor = try container.decodeIfPresent(Bool.self, forKey: .hideCursor) ?? hideCursor
    cropToFill = try container.decodeIfPresent(Bool.self, forKey: .cropToFill) ?? cropToFill
  }
}

public struct PersistedSettings: Codable, Equatable, Sendable {
  public var scaresEnabled = false
  public var onboardingCompleted = false
  public var pauseUntil: Date?
  public var schedule = ScheduleSettings()
  public var safety = SafetySettings()
  public var appearance = AppearanceSettings()
  public var totalScareCount = 0
  public var dailyScareDates: [Date] = []
  public var lastScareDate: Date?

  public init() {}

  public init(from decoder: Decoder) throws {
    self.init()
    let container = try decoder.container(keyedBy: CodingKeys.self)
    scaresEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .scaresEnabled) ?? scaresEnabled
    onboardingCompleted =
      try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? onboardingCompleted
    pauseUntil = try container.decodeIfPresent(Date.self, forKey: .pauseUntil)
    schedule = try container.decodeIfPresent(ScheduleSettings.self, forKey: .schedule) ?? schedule
    safety = try container.decodeIfPresent(SafetySettings.self, forKey: .safety) ?? safety
    appearance =
      try container.decodeIfPresent(AppearanceSettings.self, forKey: .appearance) ?? appearance
    totalScareCount =
      try container.decodeIfPresent(Int.self, forKey: .totalScareCount) ?? totalScareCount
    dailyScareDates =
      try container.decodeIfPresent([Date].self, forKey: .dailyScareDates) ?? dailyScareDates
    lastScareDate = try container.decodeIfPresent(Date.self, forKey: .lastScareDate)
  }
}

public struct VideoItem: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var displayName: String
  public var bookmarkData: Data
  public var duration: TimeInterval
  public var isEnabled: Bool
  public var volume: Double
  public var trimStart: TimeInterval
  public var trimEnd: TimeInterval?
  public var lastKnownPath: String
  public var isMissing: Bool
  public var selectionWeight: Double
  public var isRare: Bool
  public var selectionCooldown: TimeInterval
  public var lastPlayedAt: Date?

  public init(
    id: UUID = UUID(), displayName: String, bookmarkData: Data,
    duration: TimeInterval, isEnabled: Bool = true, volume: Double = 1,
    trimStart: TimeInterval = 0, trimEnd: TimeInterval? = nil,
    lastKnownPath: String, isMissing: Bool = false, selectionWeight: Double = 1,
    isRare: Bool = false, selectionCooldown: TimeInterval = 0, lastPlayedAt: Date? = nil
  ) {
    self.id = id
    self.displayName = displayName
    self.bookmarkData = bookmarkData
    self.duration = duration
    self.isEnabled = isEnabled
    self.volume = volume
    self.trimStart = trimStart
    self.trimEnd = trimEnd
    self.lastKnownPath = lastKnownPath
    self.isMissing = isMissing
    self.selectionWeight = selectionWeight
    self.isRare = isRare
    self.selectionCooldown = selectionCooldown
    self.lastPlayedAt = lastPlayedAt
    normalizePlaybackSettings()
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    displayName = try container.decode(String.self, forKey: .displayName)
    bookmarkData = try container.decode(Data.self, forKey: .bookmarkData)
    duration = try container.decode(TimeInterval.self, forKey: .duration)
    isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    volume = try container.decode(Double.self, forKey: .volume)
    trimStart = try container.decode(TimeInterval.self, forKey: .trimStart)
    trimEnd = try container.decodeIfPresent(TimeInterval.self, forKey: .trimEnd)
    lastKnownPath = try container.decode(String.self, forKey: .lastKnownPath)
    isMissing = try container.decode(Bool.self, forKey: .isMissing)
    selectionWeight =
      try container.decodeIfPresent(Double.self, forKey: .selectionWeight) ?? 1
    isRare = try container.decodeIfPresent(Bool.self, forKey: .isRare) ?? false
    selectionCooldown =
      try container.decodeIfPresent(TimeInterval.self, forKey: .selectionCooldown) ?? 0
    lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
    normalizePlaybackSettings()
  }

  public var effectiveTrimStart: TimeInterval {
    min(max(0, trimStart), max(0, duration - 0.01))
  }

  public var effectiveTrimEnd: TimeInterval {
    guard let trimEnd else { return duration }
    return min(duration, max(effectiveTrimStart + 0.01, trimEnd))
  }

  public var effectivePlaybackDuration: TimeInterval {
    max(0.01, effectiveTrimEnd - effectiveTrimStart)
  }

  public var effectiveSelectionWeight: Double {
    selectionWeight * (isRare ? 0.1 : 1)
  }

  public func isEligible(at date: Date) -> Bool {
    guard selectionCooldown > 0, let lastPlayedAt else { return true }
    return date.timeIntervalSince(lastPlayedAt) >= selectionCooldown
  }

  public mutating func normalizePlaybackSettings() {
    duration = duration.isFinite ? max(0.01, duration) : 0.01
    volume = min(1, max(0, volume))
    selectionWeight = selectionWeight.isFinite ? min(10, max(0.1, selectionWeight)) : 1
    selectionCooldown =
      selectionCooldown.isFinite ? min(30 * 24 * 60 * 60, max(0, selectionCooldown)) : 0
    trimStart = effectiveTrimStart
    guard trimEnd != nil else { return }
    let normalizedEnd = effectiveTrimEnd
    trimEnd = normalizedEnd >= duration ? nil : normalizedEnd
  }
}

public enum StartleError: LocalizedError, Sendable {
  case noVideos, onboardingRequired, emergencyShortcutUnavailable
  case videoUnavailable(String)
  case unsupportedVideo(String)
  case playbackFailed(String)

  public var errorDescription: String? {
    switch self {
    case .noVideos: "Import and enable at least one video first."
    case .onboardingRequired: "Complete onboarding before enabling scares."
    case .emergencyShortcutUnavailable:
      "The global emergency shortcut must be available before scheduled scares can be enabled. Resolve the shortcut conflict and retry registration in Safety."
    case .videoUnavailable(let name):
      "The video “\(name)” was moved, deleted, or can no longer be opened."
    case .unsupportedVideo(let name): "“\(name)” is not a playable MP4, MOV, or M4V video."
    case .playbackFailed(let detail): "Playback failed: \(detail)"
    }
  }
}
