import AppKit
import Foundation
import Observation
import os

@MainActor
protocol ScarePresenting: AnyObject {
  func present(
    video: VideoItem, url: URL, safety: SafetySettings, appearance: AppearanceSettings,
    preflight: @escaping @MainActor () -> Bool
  ) async throws -> ScarePresentationOutcome
  func dismiss()
}

extension ScareWindowController: ScarePresenting {}

@MainActor @Observable
public final class ScareCoordinator {
  public private(set) var isPresenting = false

  private let settings: SettingsStore
  private let library: VideoLibrary
  private let windowController: any ScarePresenting
  private let frontmostApplicationBundleIdentifier: @MainActor () -> String?
  private let safetyBlockReason: @MainActor () -> SafetyBlockReason?
  private let logger = Logger(subsystem: "com.startle.app", category: "coordinator")

  public convenience init(
    settings: SettingsStore, library: VideoLibrary, activity: SystemActivityMonitor
  ) {
    self.init(
      settings: settings, library: library, windowController: ScareWindowController(),
      frontmostApplicationBundleIdentifier: {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
      },
      safetyBlockReason: {
        activity.refresh()
        return activity.blockReason(
          by: settings.values.safety, schedule: settings.values.schedule)
      })
  }

  init(
    settings: SettingsStore, library: VideoLibrary, windowController: any ScarePresenting,
    frontmostApplicationBundleIdentifier: @escaping @MainActor () -> String? = {
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    },
    safetyBlockReason: @escaping @MainActor () -> SafetyBlockReason? = { nil }
  ) {
    self.settings = settings
    self.library = library
    self.windowController = windowController
    self.frontmostApplicationBundleIdentifier = frontmostApplicationBundleIdentifier
    self.safetyBlockReason = safetyBlockReason
  }

  public func trigger(isTest: Bool = false, specificVideo: VideoItem? = nil) async {
    guard !isPresenting else { return }
    if !isTest, let reason = safetyBlockReason() {
      recordSafetySkipped(reason, isTest: false)
      return
    }
    if let excludedApplication = frontmostExcludedApplication() {
      recordSkipped(
        reason: .excludedApplication, context: excludedApplication.displayName, isTest: isTest)
      return
    }
    guard let video = specificVideo ?? library.randomEnabledVideo() else {
      recordSkipped(
        reason: library.enabledVideos.isEmpty ? .noAvailableVideo : .noEligibleVideo,
        isTest: isTest)
      if !isTest && library.enabledVideos.isEmpty {
        try? settings.setEnabled(
          false, hasVideos: false, emergencyShortcutAvailable: false)
        settings.present(StartleError.noVideos)
      }
      return
    }
    isPresenting = true
    var access: (url: URL, securityScoped: Bool)?
    do {
      let resolvedAccess = try library.resolve(video)
      access = resolvedAccess
      if let excludedApplication = frontmostExcludedApplication() {
        if resolvedAccess.securityScoped {
          resolvedAccess.url.stopAccessingSecurityScopedResource()
        }
        recordSkipped(
          reason: .excludedApplication, context: excludedApplication.displayName, isTest: isTest)
        isPresenting = false
        return
      }
      var finalSafetyBlockReason: SafetyBlockReason?
      let outcome = try await windowController.present(
        video: video, url: resolvedAccess.url, safety: settings.values.safety,
        appearance: settings.values.appearance,
        preflight: { [weak self] in
          guard let self else { return false }
          guard !isTest else { return true }
          finalSafetyBlockReason = self.safetyBlockReason()
          return finalSafetyBlockReason == nil
        })
      switch outcome {
      case .completed:
        settings.recordActivity(
          ActivityEvent(kind: .played, videoName: video.displayName, isTest: isTest))
      case .dismissed:
        settings.recordActivity(
          ActivityEvent(kind: .dismissed, videoName: video.displayName, isTest: isTest))
      case .skipped:
        if let finalSafetyBlockReason {
          recordSafetySkipped(finalSafetyBlockReason, isTest: isTest)
        } else if let excludedApplication = frontmostExcludedApplication() {
          recordSkipped(
            reason: .excludedApplication, context: excludedApplication.displayName,
            isTest: isTest)
        } else {
          recordSkipped(reason: .presentationCancelled, isTest: isTest)
        }
      }
      if outcome == .completed && !isTest {
        library.recordPlayback(of: video)
        settings.recordScare()
      }
    } catch {
      settings.recordActivity(
        ActivityEvent(
          kind: .failed, reason: .playbackFailed, videoName: video.displayName, isTest: isTest))
      if !isTest && library.enabledVideos.isEmpty {
        try? settings.setEnabled(
          false, hasVideos: false, emergencyShortcutAvailable: false)
      }
      settings.present(error)
      logger.error(
        "Could not present scare: \(error.localizedDescription, privacy: .private(mask: .hash))")
    }
    if let access, access.securityScoped { access.url.stopAccessingSecurityScopedResource() }
    isPresenting = false
  }

  public func dismiss() { windowController.dismiss() }

  private func frontmostExcludedApplication() -> ExcludedApplication? {
    guard let bundleIdentifier = frontmostApplicationBundleIdentifier() else { return nil }
    return settings.values.safety.excludedApplications.first {
      $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
    }
  }

  private func recordSkipped(
    reason: ActivityEventReason, context: String? = nil, isTest: Bool
  ) {
    settings.recordActivity(
      ActivityEvent(kind: .skipped, reason: reason, context: context, isTest: isTest))
  }

  private func recordSafetySkipped(_ reason: SafetyBlockReason, isTest: Bool) {
    let activityReason: ActivityEventReason =
      switch reason {
      case .asleepOrLocked: .asleepOrLocked
      case .screenCapture: .screenCapture
      case .fullScreenApp: .fullScreenApp
      case .cameraOrMicrophone: .cameraOrMicrophone
      case .externalDisplay: .externalDisplay
      case .lowBattery: .lowBattery
      case .highVolume: .highVolume
      case .idleReturnGracePeriod: .idleReturnGracePeriod
      }
    recordSkipped(reason: activityReason, isTest: isTest)
  }
}
