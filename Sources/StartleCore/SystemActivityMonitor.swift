import AppKit
import CoreAudio
import CoreGraphics
import CoreMediaIO
import Foundation
import IOKit.ps
import Observation
import os

@MainActor @Observable
public final class SystemActivityMonitor {
    public private(set) var isAsleepOrLocked = false
    public private(set) var isScreenCaptured = false
    public private(set) var isFullScreenAppActive = false
    public private(set) var hasExternalDisplay = false
    public private(set) var batteryPercent = 100.0
    public private(set) var systemVolumePercent = 0.0
    public private(set) var recentlyReturnedFromIdle = false
    public private(set) var cameraOrMicrophoneDetected = false
    public private(set) var focusModeDetected = false
    public private(set) var lastWakeDate: Date?
    public var onWake: (@MainActor () -> Void)?

    @ObservationIgnored nonisolated(unsafe) private var pollTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    private var wasIdle = false
    private var idleReturnDate: Date?
    private let logger = Logger(subsystem: "com.startle.app", category: "activity")

    public init() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isAsleepOrLocked = true }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isAsleepOrLocked = true }
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        })
        startPolling()
    }

    deinit {
        pollTask?.cancel()
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
    }

    public func blocked(by safety: SafetySettings, schedule: ScheduleSettings) -> Bool {
        isAsleepOrLocked
            || (safety.pauseForScreenCapture && isScreenCaptured)
            || (safety.pauseForFullScreenApps && isFullScreenAppActive)
            || (safety.pauseForCameraOrMicrophone && cameraOrMicrophoneDetected)
            || (safety.pauseForFocus && focusModeDetected)
            || (safety.disableWithExternalDisplay && hasExternalDisplay)
            || batteryPercent < safety.disableBelowBatteryPercent
            || systemVolumePercent > safety.disableAboveSystemVolumePercent
            || (schedule.avoidAfterIdle && idleReturnDate.map { Date().timeIntervalSince($0) < schedule.idleGracePeriod } == true)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func handleWake() {
        isAsleepOrLocked = false
        lastWakeDate = Date()
        onWake?()
        logger.info("System became active; overdue triggers will be discarded")
    }

    private func refresh() {
        hasExternalDisplay = NSScreen.screens.count > 1
        batteryPercent = Self.readBatteryPercent() ?? 100
        systemVolumePercent = Self.readOutputVolume() ?? 0
        isScreenCaptured = Self.detectAppleScreenCaptureActivity()
        isFullScreenAppActive = Self.detectFullScreenFrontmostWindow()
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved) > 5 * 60
            && CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) > 5 * 60
        recentlyReturnedFromIdle = wasIdle && !idle
        if recentlyReturnedFromIdle {
            idleReturnDate = Date()
        }
        if let idleReturnDate, Date().timeIntervalSince(idleReturnDate) >= 3600 { recentlyReturnedFromIdle = false }
        wasIdle = idle
        cameraOrMicrophoneDetected = Self.anyCameraRunning() || Self.anyInputAudioDeviceRunning()
        // macOS has no supported API for reading the user's current Focus state.
        focusModeDetected = false
    }

    private static func detectFullScreenFrontmostWindow() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let frames = NSScreen.screens.map(\.frame)
        return list.contains { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return false }
            return frames.contains { abs($0.width - bounds.width) < 4 && abs($0.height - bounds.height) < 4 }
        }
    }

    private static func detectAppleScreenCaptureActivity() -> Bool {
        let captureBundleIDs: Set<String> = [
            "com.apple.ScreenSharing",
            "com.apple.screensharing.agent",
            "com.apple.screencaptureui"
        ]
        return NSWorkspace.shared.runningApplications.contains { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return captureBundleIDs.contains(bundleID) && !app.isTerminated
        }
    }

    private static func anyCameraRunning() -> Bool {
        var devicesAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &devicesAddress, 0, nil, &dataSize) == noErr else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(dataSize) / MemoryLayout<CMIOObjectID>.size)
        var dataUsed: UInt32 = 0
        guard !devices.isEmpty,
              CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &devicesAddress, 0, nil, dataSize, &dataUsed, &devices) == noErr else { return false }
        for device in devices {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            var running: UInt32 = 0
            let runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningUsed: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, runningSize, &runningUsed, &running) == noErr, running != 0 { return true }
        }
        return false
    }

    private static func anyInputAudioDeviceRunning() -> Bool {
        var devicesAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, 0, nil, &dataSize) == noErr else { return false }
        var devices = [AudioDeviceID](repeating: 0, count: Int(dataSize) / MemoryLayout<AudioDeviceID>.size)
        guard !devices.isEmpty,
              AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, 0, nil, &dataSize, &devices) == noErr else { return false }
        for device in devices {
            var runningAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(device, &runningAddress) else { continue }
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &runningSize, &running) == noErr, running != 0 { return true }
        }
        return false
    }

    private static func readBatteryPercent() -> Double? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
              let current = description[kIOPSCurrentCapacityKey] as? Double,
              let maximum = description[kIOPSMaxCapacityKey] as? Double, maximum > 0 else { return nil }
        return current / maximum * 100
    }

    private static func readOutputVolume() -> Double? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var volume = Float32(0); size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return Double(volume * 100)
    }
}
