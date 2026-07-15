import Foundation
import Observation
import os

@MainActor @Observable
public final class ScareCoordinator {
    public private(set) var isPresenting = false

    private let settings: SettingsStore
    private let library: VideoLibrary
    private let windowController = ScareWindowController()
    private let logger = Logger(subsystem: "com.startle.app", category: "coordinator")

    public init(settings: SettingsStore, library: VideoLibrary) {
        self.settings = settings; self.library = library
    }

    public func trigger(isTest: Bool = false, specificVideo: VideoItem? = nil) async {
        guard !isPresenting else { return }
        guard let video = specificVideo ?? library.randomEnabledVideo() else { settings.present(StartleError.noVideos); return }
        isPresenting = true
        var access: (url: URL, securityScoped: Bool)?
        do {
            access = try library.resolve(video)
            try await windowController.present(video: video, url: access!.url, safety: settings.values.safety, appearance: settings.values.appearance)
            if !isTest { settings.recordScare() }
        } catch {
            settings.present(error)
            logger.error("Could not present scare: \(error.localizedDescription, privacy: .public)")
        }
        if let access, access.securityScoped { access.url.stopAccessingSecurityScopedResource() }
        isPresenting = false
    }

    public func dismiss() { windowController.dismiss() }
}
