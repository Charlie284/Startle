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
    .commands { CommandGroup(replacing: .newItem) {} }

    MenuBarExtra {
      MenuBarContent()
        .environment(state)
    } label: {
      Image(systemName: state.settings.values.appearance.menuBarIcon.symbolName)
    }
  }

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
    Text(state.scheduler.nextWindowDescription).foregroundStyle(.secondary)
    Divider()
    Button("Trigger Test Scare") { state.testScare() }.disabled(state.library.enabledVideos.isEmpty)
    Button("Pause for 1 Hour") { state.pauseOneHour() }.disabled(
      !state.settings.values.scaresEnabled)
    Divider()
    Button("Open Startle…") {
      openWindow(id: "main")
      NSApp.activate()
    }
    Button("Quit Startle") { NSApplication.shared.terminate(nil) }
      .keyboardShortcut("q")
  }
}
