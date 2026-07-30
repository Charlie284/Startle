import Carbon
import Foundation
import Observation

@MainActor @Observable
public final class EmergencyShortcutManager {
  @ObservationIgnored nonisolated(unsafe) private var hotKey: EventHotKeyRef?
  @ObservationIgnored nonisolated(unsafe) private var handler: EventHandlerRef?
  private let action: () -> Void
  @ObservationIgnored private let registrationAttempt: (() -> String?)?
  public private(set) var isRegistered = false
  public private(set) var errorMessage: String?

  public convenience init(action: @escaping () -> Void) {
    self.init(action: action, registrationAttempt: nil)
  }

  init(action: @escaping () -> Void, registrationAttempt: (() -> String?)?) {
    self.action = action
    self.registrationAttempt = registrationAttempt
    register()
  }

  public func register() {
    guard !isRegistered else { return }
    errorMessage = nil
    if let registrationAttempt {
      if let error = registrationAttempt() {
        errorMessage = error
      } else {
        isRegistered = true
      }
      return
    }
    var type = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    let handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, userData in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        let manager = Unmanaged<EmergencyShortcutManager>.fromOpaque(userData).takeUnretainedValue()
        Task { @MainActor in manager.action() }
        return noErr
      }, 1, &type, pointer, &handler)
    guard handlerStatus == noErr else {
      errorMessage =
        "The emergency shortcut handler could not be installed (error \(handlerStatus)). Escape still closes an active scare."
      return
    }
    let id = EventHotKeyID(signature: OSType(0x5354_5254), id: 1)  // STRT
    let hotKeyStatus = RegisterEventHotKey(
      UInt32(kVK_Escape),
      UInt32(cmdKey | optionKey | shiftKey),
      id,
      GetApplicationEventTarget(),
      0,
      &hotKey
    )
    guard hotKeyStatus == noErr else {
      if let handler {
        RemoveEventHandler(handler)
        self.handler = nil
      }
      errorMessage =
        "The global emergency shortcut is unavailable, usually because another app already uses it (error \(hotKeyStatus)). Escape still closes an active scare."
      return
    }
    isRegistered = true
  }

  public func clearError() { errorMessage = nil }

  deinit {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    if let handler { RemoveEventHandler(handler) }
  }
}
