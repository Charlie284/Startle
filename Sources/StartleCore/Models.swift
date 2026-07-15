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

public enum MenuBarIconStyle: String, Codable, CaseIterable, Sendable {
    case eye, warning, ghost
    public var title: String { rawValue.capitalized }
    public var symbolName: String {
        switch self { case .eye: "eye.fill"; case .warning: "exclamationmark.triangle.fill"; case .ghost: "theatermasks.fill" }
    }
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
}

public struct SafetySettings: Codable, Equatable, Sendable {
    public var pauseForCameraOrMicrophone = true
    public var pauseForScreenCapture = true
    public var pauseForFullScreenApps = true
    public var pauseForFocus = true
    public var disableWithExternalDisplay = false
    public var disableBelowBatteryPercent = 15.0
    public var disableAboveSystemVolumePercent = 85.0
    public var quietMode = false
    public var countdownSeconds = 0
    public var neverRunAtLogin = true

    public init() {}
}

public struct AppearanceSettings: Codable, Equatable, Sendable {
    public var theme: AppTheme = .system
    public var menuBarIcon: MenuBarIconStyle = .eye
    public var displayMode: ScareDisplayMode = .fullScreen
    public var backgroundHex = "09090B"
    public var hideCursor = true
    public var cropToFill = false

    public init() {}
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

    public init(
        id: UUID = UUID(), displayName: String, bookmarkData: Data,
        duration: TimeInterval, isEnabled: Bool = true, volume: Double = 1,
        trimStart: TimeInterval = 0, trimEnd: TimeInterval? = nil,
        lastKnownPath: String, isMissing: Bool = false
    ) {
        self.id = id; self.displayName = displayName; self.bookmarkData = bookmarkData
        self.duration = duration; self.isEnabled = isEnabled; self.volume = volume
        self.trimStart = trimStart; self.trimEnd = trimEnd
        self.lastKnownPath = lastKnownPath; self.isMissing = isMissing
    }
}

public enum StartleError: LocalizedError, Sendable {
    case noVideos, onboardingRequired, videoUnavailable(String), unsupportedVideo(String), playbackFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noVideos: "Import and enable at least one video first."
        case .onboardingRequired: "Complete onboarding before enabling scares."
        case .videoUnavailable(let name): "The video “\(name)” was moved, deleted, or can no longer be opened."
        case .unsupportedVideo(let name): "“\(name)” is not a playable MP4, MOV, or M4V video."
        case .playbackFailed(let detail): "Playback failed: \(detail)"
        }
    }
}
