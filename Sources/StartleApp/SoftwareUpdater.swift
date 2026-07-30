import Foundation
import Observation
import Sparkle

@MainActor @Observable
final class SoftwareUpdater {
  @ObservationIgnored private let controller: SPUStandardUpdaterController
  @ObservationIgnored private var canCheckForUpdatesObservation: NSKeyValueObservation?

  private(set) var canCheckForUpdates = false

  init() {
    let controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
    self.controller = controller
    canCheckForUpdatesObservation = controller.updater.observe(
      \.canCheckForUpdates,
      options: [.initial, .new]
    ) { [weak self] _, change in
      let canCheckForUpdates = change.newValue ?? false
      Task { @MainActor [weak self] in
        self?.canCheckForUpdates = canCheckForUpdates
      }
    }
  }

  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }
}
