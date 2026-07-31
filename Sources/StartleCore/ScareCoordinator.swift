import AppKit
import Foundation
import Observation
import os

@MainActor
protocol ScarePresenting: AnyObject {
  func present(
    video: VideoItem, url: URL, safety: SafetySettings, appearance: AppearanceSettings
  ) async throws -> Bool
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
  private let logger = Logger(subsystem: "com.startle.app", category: "coordinator")

  public convenience init(settings: SettingsStore, library: VideoLibrary) {
    self.init(
      settings: settings, library: library, windowController: ScareWindowController(),
      frontmostApplicationBundleIdentifier: {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
      })
  }

  init(
    settings: SettingsStore, library: VideoLibrary, windowController: any ScarePresenting,
    frontmostApplicationBundleIdentifier: @escaping @MainActor () -> String? = {
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
  ) {
    self.settings = settings
    self.library = library
    self.windowController = windowController
    self.frontmostApplicationBundleIdentifier = frontmostApplicationBundleIdentifier
  }

  public func trigger(isTest: Bool = false, specificVideo: VideoItem? = nil) async {
    guard !isPresenting else { return }
    guard
      !settings.values.safety.excludesApplication(
        bundleIdentifier: frontmostApplicationBundleIdentifier())
    else { return }
    guard let video = specificVideo ?? library.randomEnabledVideo() else {
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
      guard
        !settings.values.safety.excludesApplication(
          bundleIdentifier: frontmostApplicationBundleIdentifier())
      else {
        if resolvedAccess.securityScoped {
          resolvedAccess.url.stopAccessingSecurityScopedResource()
        }
        isPresenting = false
        return
      }
      let wasPresented = try await windowController.present(
        video: video, url: resolvedAccess.url, safety: settings.values.safety,
        appearance: settings.values.appearance)
      if wasPresented && !isTest {
        library.recordPlayback(of: video)
        settings.recordScare()
      }
    } catch {
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
}
