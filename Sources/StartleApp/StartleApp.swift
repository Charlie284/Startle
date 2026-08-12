import AppKit
import StartleCore
import SwiftUI

@main
struct StartleApp: App {
  @State private var state = AppState()

  var body: some Scene {
    WindowGroup("Startle", id: "main") {
      ContentView()
        .environment(state)
        .preferredColorScheme(colorScheme)
        .frame(minWidth: 880, minHeight: 540)
    }
    .defaultSize(width: 1050, height: 610)
    .commands {
      CommandGroup(replacing: .newItem) {}
      CommandGroup(after: .appInfo) {
        Button("Check for Updates…") { state.softwareUpdater.checkForUpdates() }
          .disabled(!state.softwareUpdater.canCheckForUpdates)
      }
    }

    Window("Choose Date & Time", id: "custom-pause") {
      CustomPauseView()
        .environment(state)
        .preferredColorScheme(colorScheme)
    }
    .defaultSize(width: 420, height: 210)
    .windowResizability(.contentSize)

    MenuBarExtra {
      MenuBarContent()
        .environment(state)
    } label: {
      Image(nsImage: Self.menuBarIcon)
        .renderingMode(.template)
        .foregroundStyle(.primary)
        .accessibilityLabel("Startle")
    }
  }

  private static let menuBarIcon: NSImage = {
    let image =
      NSImage(named: "StartleMenuBarIcon")
      ?? NSImage(systemSymbolName: "eye.fill", accessibilityDescription: "Startle")
      ?? NSImage(size: NSSize(width: 18, height: 18))
    image.isTemplate = true
    image.size = NSSize(width: 18, height: 18)
    return image
  }()

  private var colorScheme: ColorScheme? {
    switch state.settings.values.appearance.theme {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

private struct MenuBarContent: View {
  @Environment(AppState.self) private var state
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Toggle(
      "Scares Enabled",
      isOn: Binding(get: { state.settings.values.scaresEnabled }, set: state.setEnabled))
    Text(menuBarStatusDescription).foregroundStyle(.secondary)
    Divider()
    Button("Trigger Test Scare") { state.testScare() }.disabled(state.library.enabledVideos.isEmpty)
    Menu("Pause") {
      Button("15 Minutes") { state.pause(for: 15 * 60) }
      Button("1 Hour") { state.pause(for: 60 * 60) }
      Button("4 Hours…") { state.pause(for: 4 * 60 * 60) }
      Button("Until Tomorrow") { state.pauseUntilTomorrow() }
      Button("Until Next Active Window") { state.pauseUntilNextActiveWindow() }
      Divider()
      Button("Choose Date & Time…") {
        openWindow(id: "custom-pause")
        NSApp.activate()
      }
    }
    .disabled(!state.settings.values.scaresEnabled)
    Button("Resume Now") { state.resumeNow() }
      .disabled(!hasActivePause)
    Divider()
    Button("Open Startle…") {
      openWindow(id: "main")
      NSApp.activate()
    }
    Button("Check for Updates…") { state.softwareUpdater.checkForUpdates() }
      .disabled(!state.softwareUpdater.canCheckForUpdates)
    Button("Quit Startle") { NSApplication.shared.terminate(nil) }
      .keyboardShortcut("q")
  }

  private var hasActivePause: Bool {
    guard let pauseUntil = state.settings.values.pauseUntil else { return false }
    return pauseUntil > Date()
  }

  private var menuBarStatusDescription: String {
    switch state.currentStatus() {
    case .disabled:
      "Scares are disabled"
    case .ready(let nextTrigger):
      nextTrigger.map {
        "Next check around " + $0.formatted(date: .omitted, time: .shortened)
      } ?? "Scheduling…"
    case .blocked(.paused(let until)):
      "Paused until " + until.formatted(date: .omitted, time: .shortened)
    case .blocked(.safety(let reason)):
      "Blocked: " + reason.menuBarDescription
    case .blocked(.outsideActiveWindow):
      "Blocked: outside active hours"
    case .blocked(.dailyLimit):
      "Blocked: daily limit reached"
    case .blocked(.cooldown(let until)):
      "Cooling down until " + until.formatted(date: .omitted, time: .shortened)
    case .blocked(.excludedApplication(let name)):
      "Blocked while using " + name
    case .blocked(.videoCooldown(let until)):
      until.map {
        "Videos cooling down until " + $0.formatted(date: .omitted, time: .shortened)
      } ?? "Videos are temporarily unavailable"
    }
  }
}

private struct CustomPauseView: View {
  @Environment(AppState.self) private var state
  @Environment(\.dismiss) private var dismiss
  @State private var pauseUntil = Date().addingTimeInterval(4 * 60 * 60)

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Choose when Startle should resume")
          .font(.headline)
        Text("Scares stay paused until this date and time.")
          .foregroundStyle(.secondary)
      }

      DatePicker(
        "Resume at", selection: $pauseUntil, in: Date()...,
        displayedComponents: [.date, .hourAndMinute]
      )

      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Pause") {
          state.pause(until: pauseUntil)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!state.settings.values.scaresEnabled || pauseUntil <= Date())
      }
    }
    .padding(24)
    .frame(width: 420)
    .onAppear {
      let defaultPause = Date().addingTimeInterval(4 * 60 * 60)
      pauseUntil = max(state.settings.values.pauseUntil ?? defaultPause, defaultPause)
    }
  }
}

extension SafetyBlockReason {
  fileprivate var menuBarDescription: String {
    switch self {
    case .asleepOrLocked: "Mac asleep or locked"
    case .screenCapture: "screen capture active"
    case .fullScreenApp: "full-screen app active"
    case .cameraOrMicrophone: "camera or microphone active"
    case .externalDisplay: "external display connected"
    case .lowBattery: "battery below safety limit"
    case .highVolume: "volume above safety limit"
    case .idleReturnGracePeriod: "return-from-idle grace period"
    }
  }
}
