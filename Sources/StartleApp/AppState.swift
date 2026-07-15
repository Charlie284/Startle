import AppKit
import Foundation
import Observation
import StartleCore
import UniformTypeIdentifiers

@MainActor @Observable
final class AppState {
    let settings: SettingsStore
    let library: VideoLibrary
    let activity: SystemActivityMonitor
    let scheduler: ScareScheduler
    let coordinator: ScareCoordinator
    let launchAtLogin: LaunchAtLoginManager
    private var emergencyShortcut: EmergencyShortcutManager!

    init() {
        let settings = SettingsStore()
        let library = VideoLibrary()
        let activity = SystemActivityMonitor()
        self.settings = settings; self.library = library; self.activity = activity
        scheduler = ScareScheduler(settings: settings, activity: activity)
        coordinator = ScareCoordinator(settings: settings, library: library)
        launchAtLogin = LaunchAtLoginManager()
        emergencyShortcut = EmergencyShortcutManager { [weak self] in self?.emergencyDisable() }
        scheduler.onTrigger = { [weak self] in await self?.coordinator.trigger() }
        activity.onWake = { [weak scheduler] in scheduler?.reschedule() }
        if settings.values.scaresEnabled && (!settings.values.onboardingCompleted || library.enabledVideos.isEmpty) {
            try? settings.setEnabled(false, hasVideos: false)
        }
        scheduler.reschedule()
    }

    var combinedError: String? { settings.errorMessage ?? library.errorMessage ?? launchAtLogin.errorMessage }

    func clearError() { settings.clearError(); library.clearError() }

    func setEnabled(_ enabled: Bool) {
        do { try settings.setEnabled(enabled, hasVideos: !library.enabledVideos.isEmpty); scheduler.reschedule() }
        catch { settings.present(error) }
    }

    func scheduleChanged() { scheduler.reschedule() }

    func pauseOneHour() { settings.pause(for: 3600); scheduler.reschedule() }

    func emergencyDisable() {
        coordinator.dismiss()
        setEnabled(false)
    }

    func testScare(video: VideoItem? = nil) { Task { await coordinator.trigger(isTest: true, specificVideo: video) } }

    func chooseVideos() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
        panel.message = "Choose one or more videos for Startle"
        guard panel.runModal() == .OK else { return }
        importVideos(panel.urls)
    }

    func importVideos(_ urls: [URL]) {
        Task {
            _ = await library.importVideos(from: urls)
            if settings.values.scaresEnabled && library.enabledVideos.isEmpty { setEnabled(false) }
            scheduler.reschedule()
        }
    }

    func removeVideo(_ item: VideoItem) {
        library.remove(item)
        if library.enabledVideos.isEmpty { setEnabled(false) }
    }
}
