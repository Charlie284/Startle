import StartleCore
import SwiftUI

struct DashboardView: View {
  @Environment(AppState.self) private var state

  var body: some View {
    Page(title: "Dashboard", subtitle: "A calm overview of future chaos.") {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 20) {
          scareControls
            .frame(minWidth: 420, maxWidth: .infinity)
            .layoutPriority(1)
          activitySummary
            .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
        }

        VStack(alignment: .leading, spacing: 16) {
          scareControls
          activitySummary
        }
      }
    }
  }

  private var scareControls: some View {
    GroupBox("Scare controls") {
      VStack(alignment: .leading, spacing: 16) {
        Toggle(
          isOn: Binding(get: { state.settings.values.scaresEnabled }, set: state.setEnabled)
        ) {
          VStack(alignment: .leading, spacing: 5) {
            Text("Enable scares").font(.headline)
            Text(
              state.settings.values.scaresEnabled
                ? "Startle is waiting in the background."
                : "Nothing will play until you enable Startle."
            ).foregroundStyle(.secondary)
          }
        }
        .toggleStyle(.switch)
        .accessibilityLabel("Enable scares")
        .accessibilityHint(
          state.settings.values.scaresEnabled
            ? "Turns off scheduled scares."
            : "Turns on scheduled scares when an enabled video is available."
        )

        Divider()

        HStack(alignment: .firstTextBaseline, spacing: 16) {
          Label("Next scare", systemImage: "clock")
            .foregroundStyle(.purple)
          Spacer(minLength: 16)
          Text(state.scheduler.nextWindowDescription)
            .font(.headline)
            .multilineTextAlignment(.trailing)
        }

        HStack(spacing: 12) {
          Button("Test Jumpscare", systemImage: "play.fill") { state.testScare() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(state.library.enabledVideos.isEmpty)
          Button("Pause for 1 Hour", systemImage: "cup.and.saucer") { state.pauseOneHour() }
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(!state.settings.values.scaresEnabled)
        }

        if let pause = state.settings.values.pauseUntil, pause > Date() {
          Label(
            "Paused until \(pause.formatted(date: .omitted, time: .shortened))",
            systemImage: "moon.zzz.fill"
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }
      }
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var activitySummary: some View {
    GroupBox("At a glance") {
      VStack(spacing: 0) {
        SummaryRow(
          title: "Status",
          value: state.settings.values.scaresEnabled ? "Armed" : "Disabled",
          icon: state.settings.values.scaresEnabled ? "bolt.fill" : "pause.fill",
          tint: state.settings.values.scaresEnabled ? .orange : .secondary)
        Divider()
        SummaryRow(
          title: "Ready videos", value: "\(state.library.enabledVideos.count)",
          icon: "play.rectangle.on.rectangle", tint: .purple)
        Divider()
        SummaryRow(
          title: "Today", value: "\(state.settings.scaresToday())", icon: "calendar", tint: .blue)
        Divider()
        SummaryRow(
          title: "All time", value: "\(state.settings.values.totalScareCount)", icon: "number",
          tint: .pink)
      }
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct SummaryRow: View {
  let title: String
  let value: String
  let icon: String
  let tint: Color

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .foregroundStyle(tint)
        .frame(width: 18)
      Text(title)
        .foregroundStyle(.secondary)
      Spacer(minLength: 12)
      Text(value)
        .font(.headline.monospacedDigit())
    }
    .padding(.vertical, 12)
  }
}
