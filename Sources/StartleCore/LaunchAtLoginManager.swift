import Foundation
import Observation
import ServiceManagement

@MainActor
protocol LaunchAtLoginService: AnyObject {
  var status: SMAppService.Status { get }
  func register() throws
  func unregister() throws
}

extension SMAppService: LaunchAtLoginService {}

@MainActor @Observable
public final class LaunchAtLoginManager {
  public private(set) var isEnabled = false
  public private(set) var requiresApproval = false
  public private(set) var errorMessage: String?
  private let service: any LaunchAtLoginService

  public convenience init() { self.init(service: SMAppService.mainApp) }

  init(service: any LaunchAtLoginService) {
    self.service = service
    refresh()
  }

  public func refresh() {
    switch service.status {
    case .enabled:
      isEnabled = true
      requiresApproval = false
    case .requiresApproval:
      isEnabled = true
      requiresApproval = true
    case .notRegistered, .notFound:
      isEnabled = false
      requiresApproval = false
    @unknown default:
      isEnabled = false
      requiresApproval = false
    }
  }
  public func clearError() { errorMessage = nil }
  public func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }

  public func reconcile(forbidden: Bool) {
    refresh()
    guard forbidden, service.status == .enabled || service.status == .requiresApproval else {
      return
    }
    setEnabled(false, forbidden: false)
  }

  public func setEnabled(_ enabled: Bool, forbidden: Bool) {
    guard !forbidden || !enabled else { return }
    if enabled, service.status == .enabled || service.status == .requiresApproval {
      refresh()
      return
    }
    do {
      if enabled {
        try service.register()
      } else {
        try service.unregister()
      }
      refresh()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
      refresh()
    }
  }
}
