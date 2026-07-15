import Foundation
import Observation
import ServiceManagement

@MainActor @Observable
public final class LaunchAtLoginManager {
    public private(set) var isEnabled = false
    public private(set) var errorMessage: String?

    public init() { refresh() }

    public func refresh() { isEnabled = SMAppService.mainApp.status == .enabled }

    public func setEnabled(_ enabled: Bool, forbidden: Bool) {
        guard !forbidden || !enabled else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refresh(); errorMessage = nil
        } catch { errorMessage = error.localizedDescription; refresh() }
    }
}
