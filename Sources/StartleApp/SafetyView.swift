import AppKit
import StartleCore
import SwiftUI

struct SafetyView: View {
  @Environment(AppState.self) private var state
  var body: some View {
    @Bindable var store = state.settings
    Page(title: "Safety", subtitle: "Strong brakes are part of the prank.") {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: "heart.slash.fill").font(.title).foregroundStyle(.red)
        VStack(alignment: .leading, spacing: 5) {
          Text("Health warning").font(.headline)
          Text(
            "Do not use Startle on anyone with a heart condition, epilepsy, severe anxiety, PTSD, or sound sensitivity. Get clear consent and never use it where a sudden reaction could cause injury."
          )
        }
      }.padding(16).background(Color.red.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))

      GroupBox("Emergency controls") {
        VStack(alignment: .leading, spacing: 12) {
          LabeledContent("Master emergency disable") {
            Text(state.emergencyShortcutIsRegistered ? "⌘⌥⇧ Esc" : "Unavailable")
              .font(.system(.body, design: .monospaced).bold())
              .foregroundStyle(state.emergencyShortcutIsRegistered ? Color.primary : Color.red)
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
          }
          Label("Escape always closes the active scare immediately.", systemImage: "escape")
          if !state.emergencyShortcutIsRegistered {
            Button("Retry Shortcut Registration") { state.retryEmergencyShortcut() }
          }
          Button("Disable Now", role: .destructive) { state.emergencyDisable() }
        }.padding(8)
      }

      GroupBox("Automatic pauses") {
        VStack(alignment: .leading, spacing: 12) {
          Toggle(
            "Pause while camera or microphone use is detectable",
            isOn: $store.values.safety.pauseForCameraOrMicrophone)
          Toggle(
            "Pause during screen recording or screen sharing",
            isOn: $store.values.safety.pauseForScreenCapture)
          Toggle(
            "Pause over full-screen games, presentations, or videos",
            isOn: $store.values.safety.pauseForFullScreenApps)
          LabeledContent("Focus / Do Not Disturb") {
            Text("Unavailable through public macOS APIs")
              .foregroundStyle(.secondary)
          }
          Divider()
          Label(
            "Startle uses public device-running signals for camera and microphone activity, plus supported app signals for Apple screen capture. Third-party sharing may be undetectable; no private APIs are used.",
            systemImage: "info.circle"
          ).font(.caption).foregroundStyle(.secondary)
        }.padding(8)
      }

      GroupBox("Excluded apps") {
        VStack(alignment: .leading, spacing: 12) {
          Text(
            "Startle checks the frontmost app immediately before firing and stays inactive for every app in this list. This is local and doesn't require Accessibility permission."
          )
          .font(.callout)
          .foregroundStyle(.secondary)

          if store.values.safety.excludedApplications.isEmpty {
            ContentUnavailableView(
              "No Excluded Apps", systemImage: "app.badge",
              description: Text("Add presentation, recording, game, or editing apps here.")
            )
            .frame(maxWidth: .infinity)
          } else {
            ForEach(store.values.safety.excludedApplications) { application in
              HStack(spacing: 10) {
                ExcludedApplicationIcon(bundleIdentifier: application.bundleIdentifier)
                VStack(alignment: .leading, spacing: 2) {
                  Text(application.displayName)
                  Text(application.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
                Spacer()
                Button("Remove", systemImage: "trash", role: .destructive) {
                  state.removeExcludedApplication(application)
                }
                .labelStyle(.iconOnly)
                .help("Remove \(application.displayName) from exclusions")
              }
              .padding(.vertical, 2)
            }
          }

          Button("Add App…", systemImage: "plus") { state.chooseExcludedApplication() }
        }.padding(8)
      }

      GroupBox("Environment limits") {
        VStack(alignment: .leading, spacing: 14) {
          Toggle(
            "Disable when an external display is connected",
            isOn: $store.values.safety.disableWithExternalDisplay)
          HStack {
            Text("Disable below battery")
            Slider(value: $store.values.safety.disableBelowBatteryPercent, in: 0...50, step: 5)
            Text("\(Int(store.values.safety.disableBelowBatteryPercent))%").monospacedDigit().frame(
              width: 38)
          }
          HStack {
            Text("Disable above system volume")
            Slider(
              value: $store.values.safety.disableAboveSystemVolumePercent, in: 10...100, step: 5)
            Text("\(Int(store.values.safety.disableAboveSystemVolumePercent))%").monospacedDigit()
              .frame(width: 38)
          }
          Toggle("Quiet mode (play without sound)", isOn: $store.values.safety.quietMode)
          Picker("Accessibility countdown", selection: $store.values.safety.countdownSeconds) {
            Text("Off").tag(0)
            Text("3 seconds").tag(3)
            Text("5 seconds").tag(5)
            Text("10 seconds").tag(10)
          }.frame(maxWidth: 360)
        }.padding(8)
      }

      GroupBox("Login") {
        VStack(alignment: .leading, spacing: 12) {
          Toggle("Never run Startle at login", isOn: $store.values.safety.neverRunAtLogin)
            .onChange(of: store.values.safety.neverRunAtLogin) { _, forbidden in
              if forbidden { state.launchAtLogin.setEnabled(false, forbidden: false) }
            }
          Toggle(
            "Launch at login",
            isOn: Binding(
              get: { state.launchAtLogin.isEnabled },
              set: {
                state.launchAtLogin.setEnabled($0, forbidden: store.values.safety.neverRunAtLogin)
              })
          )
          .disabled(store.values.safety.neverRunAtLogin)
        }.padding(8)
      }
    }
  }
}

private struct ExcludedApplicationIcon: View {
  let bundleIdentifier: String

  var body: some View {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        .resizable()
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    } else {
      Image(systemName: "app")
        .font(.title2)
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }
  }
}
