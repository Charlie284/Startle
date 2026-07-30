import AppKit
import StartleCore
import SwiftUI

struct AppearanceView: View {
  @Environment(AppState.self) private var state
  var body: some View {
    @Bindable var store = state.settings
    Page(title: "Appearance", subtitle: "Tune how Startle looks before—and during—the surprise.") {
      GroupBox("App") {
        VStack(alignment: .leading, spacing: 14) {
          Picker("Theme", selection: $store.values.appearance.theme) {
            ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) }
          }.pickerStyle(.segmented)
          Picker("Menu bar icon", selection: $store.values.appearance.menuBarIcon) {
            ForEach(MenuBarIconStyle.allCases, id: \.self) {
              Label($0.title, systemImage: $0.symbolName).tag($0)
            }
          }.frame(maxWidth: 360)
        }.padding(8)
      }
      GroupBox("Scare display") {
        VStack(alignment: .leading, spacing: 14) {
          Picker("Display mode", selection: $store.values.appearance.displayMode) {
            ForEach(ScareDisplayMode.allCases, id: \.self) { Text($0.title).tag($0) }
          }.frame(maxWidth: 420)
          ColorPicker(
            "Loading background",
            selection: hexColorBinding($store.values.appearance.backgroundHex),
            supportsOpacity: false)
          Toggle("Crop video to fill", isOn: $store.values.appearance.cropToFill)
          Toggle("Hide cursor during playback", isOn: $store.values.appearance.hideCursor)
        }.padding(8)
      }
    }
  }

  private func hexColorBinding(_ value: Binding<String>) -> Binding<Color> {
    Binding(
      get: { Color(hex: value.wrappedValue) },
      set: { color in
        if let components = NSColor(color).usingColorSpace(.deviceRGB) {
          value.wrappedValue = String(
            format: "%02X%02X%02X", Int(components.redComponent * 255),
            Int(components.greenComponent * 255), Int(components.blueComponent * 255))
        }
      })
  }
}

extension Color {
  fileprivate init(hex: String) {
    let value = Int(hex, radix: 16) ?? 0x09090B
    self.init(
      red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
      blue: Double(value & 255) / 255)
  }
}

struct AboutView: View {
  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development"
  }

  var body: some View {
    Page(title: "About", subtitle: "A tiny utility with an outsized sense of timing.") {
      VStack(spacing: 14) {
        Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(
          width: 112, height: 112)
        Text("Startle").font(.largeTitle.bold())
        Text("Version \(version)").foregroundStyle(.secondary)
        Text("Native SwiftUI • AVFoundation playback • privacy-minded local storage")
          .foregroundStyle(.secondary)
        Divider().frame(width: 380)
        Text(
          "Startle never uploads your videos. Imported files remain where you put them and are reopened through security-scoped bookmarks."
        ).multilineTextAlignment(.center).frame(maxWidth: 520)
      }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }
  }
}
