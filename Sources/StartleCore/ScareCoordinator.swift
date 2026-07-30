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
  private let logger = Logger(subsystem: "com.startle.app", category: "coordinator")

  public convenience init(settings: SettingsStore, library: VideoLibrary) {
    self.init(
      settings: settings, library: library, windowController: ScareWindowController())
  }

  init(
    settings: SettingsStore, library: VideoLibrary, windowController: any ScarePresenting
  ) {
    self.settings = settings
    self.library = library
    self.windowController = windowController
  }

  public func trigger(isTest: Bool = false, specificVideo: VideoItem? = nil) async {
    guard !isPresenting else { return }
    guard let video = specificVideo ?? library.randomEnabledVideo() else {
      if !isTest {
        try? settings.setEnabled(
          false, hasVideos: false, emergencyShortcutAvailable: false)
      }
      settings.present(StartleError.noVideos)
      return
    }
    isPresenting = true
    var access: (url: URL, securityScoped: Bool)?
    do {
      let resolvedAccess = try library.resolve(video)
      access = resolvedAccess
      let wasPresented = try await windowController.present(
        video: video, url: resolvedAccess.url, safety: settings.values.safety,
        appearance: settings.values.appearance)
      if wasPresented && !isTest { settings.recordScare() }
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
