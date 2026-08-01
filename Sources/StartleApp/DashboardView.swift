import StartleCore
import SwiftUI

struct DashboardView: View {
  @Environment(AppState.self) private var state
  @State private var confirmClearHistory = false

  var body: some View {
    Page(title: "Dashboard", subtitle: "A calm overview of future chaos.") {
      liveStatusCard
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
      activityHistory
    }
    .confirmationDialog(
      "Clear activity history?", isPresented: $confirmClearHistory, titleVisibility: .visible
    ) {
      Button("Clear History", role: .destructive) { state.settings.clearActivityHistory() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This removes Startle's locally stored played, skipped, dismissed, and failed events.")
    }
  }

  private var liveStatusCard: some View {
    TimelineView(.periodic(from: .now, by: 15)) { context in
      let status = state.currentStatus(at: context.date)
      GroupBox("Live status") {
        HStack(alignment: .top, spacing: 14) {
          Image(systemName: status.systemImage)
            .font(.title2)
            .foregroundStyle(status.tint)
            .frame(width: 28)
          VStack(alignment: .leading, spacing: 4) {
            Text(status.title).font(.headline)
            Text(status.detail).foregroundStyle(.secondary)
          }
          Spacer(minLength: 12)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
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
          Label("Next scheduling check", systemImage: "clock")
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
          Menu("Pause…", systemImage: "cup.and.saucer") {
            Button("15 Minutes") { state.pause(for: 15 * 60) }
            Button("1 Hour") { state.pause(for: 60 * 60) }
            Button("Until Tomorrow") { state.pauseUntilTomorrow() }
            Button("Until Next Active Window") { state.pauseUntilNextActiveWindow() }
          }
          .controlSize(.large)
          .frame(maxWidth: .infinity)
          .disabled(!state.settings.values.scaresEnabled)
          Button("Resume Now", systemImage: "play") { state.resumeNow() }
            .controlSize(.large)
            .disabled(!hasActivePause)
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
          value: state.currentStatus().title,
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

  private var hasActivePause: Bool {
    guard let pauseUntil = state.settings.values.pauseUntil else { return false }
    return pauseUntil > Date()
  }

  private var activityHistory: some View {
    GroupBox("Activity history") {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text("Stored only on this Mac • last 50 events")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Clear History…", role: .destructive) { confirmClearHistory = true }
            .disabled(state.settings.values.activityEvents.isEmpty)
        }
        .padding(8)

        if state.settings.values.activityEvents.isEmpty {
          ContentUnavailableView(
            "No Activity Yet", systemImage: "clock.arrow.circlepath",
            description: Text("Played, skipped, dismissed, and failed events will appear here.")
          )
          .frame(maxWidth: .infinity, minHeight: 150)
        } else {
          ForEach(Array(state.settings.values.activityEvents.enumerated()), id: \.element.id) {
            index, event in
            ActivityEventRow(event: event)
            if index < state.settings.values.activityEvents.count - 1 { Divider() }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct ActivityEventRow: View {
  let event: ActivityEvent

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: event.systemImage)
        .foregroundStyle(event.tint)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 7) {
          Text(event.title).font(.headline)
          if event.isTest {
            Text("TEST")
              .font(.caption2.bold())
              .padding(.horizontal, 5)
              .padding(.vertical, 2)
              .background(.quaternary, in: Capsule())
          }
        }
        if let detail = event.detail {
          Text(detail).font(.callout).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 12)
      Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(10)
  }
}

extension SchedulerStatus {
  fileprivate var title: String {
    switch self {
    case .disabled: "Disabled"
    case .ready: "Ready"
    case .blocked(.paused): "Paused"
    case .blocked: "Temporarily blocked"
    }
  }

  fileprivate var detail: String {
    switch self {
    case .disabled:
      "Scheduled scares are off."
    case .ready(let nextTrigger):
      if let nextTrigger {
        "Eligible now. The next scheduling check is around \(nextTrigger.formatted(date: .omitted, time: .shortened))."
      } else {
        "Eligible now. Startle is preparing the next scheduling check."
      }
    case .blocked(.paused(let until)):
      "Paused until \(until.formatted(date: .abbreviated, time: .shortened))."
    case .blocked(.safety(let reason)):
      reason.statusDescription
    case .blocked(.outsideActiveWindow):
      "The current day or time is outside your active window."
    case .blocked(.dailyLimit):
      "Today's maximum scare count has been reached."
    case .blocked(.cooldown(let until)):
      "Cooling down until \(until.formatted(date: .omitted, time: .shortened))."
    case .blocked(.excludedApplication(let name)):
      "\(name) is the frontmost excluded app."
    case .blocked(.videoCooldown(let until)):
      if let until {
        "Every enabled video is cooling down until at least \(until.formatted(date: .omitted, time: .shortened))."
      } else {
        "Every enabled video is temporarily unavailable."
      }
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .disabled: "pause.circle.fill"
    case .ready: "checkmark.circle.fill"
    case .blocked(.paused): "moon.zzz.fill"
    case .blocked: "shield.fill"
    }
  }

  fileprivate var tint: Color {
    switch self {
    case .disabled: .secondary
    case .ready: .green
    case .blocked(.paused): .blue
    case .blocked: .orange
    }
  }
}

extension SafetyBlockReason {
  fileprivate var statusDescription: String {
    switch self {
    case .asleepOrLocked: "The Mac is asleep or the session is locked."
    case .screenCapture: "Screen recording or Apple screen sharing is active."
    case .fullScreenApp: "A full-screen app is active."
    case .cameraOrMicrophone: "Camera or microphone use is detectable."
    case .externalDisplay: "An external display is connected."
    case .lowBattery: "Battery level is below your configured safety limit."
    case .highVolume: "System volume is above your configured safety limit."
    case .idleReturnGracePeriod: "Waiting through the return-from-idle grace period."
    }
  }
}

extension ActivityEvent {
  fileprivate var title: String {
    switch kind {
    case .played: "Played \(videoName ?? "a video")"
    case .skipped: "Skipped a scheduling check"
    case .dismissed: "Dismissed \(videoName ?? "a video")"
    case .failed: "Failed to play \(videoName ?? "a video")"
    }
  }

  fileprivate var detail: String? {
    guard let reason else { return nil }
    return switch reason {
    case .paused: "A manual pause was active."
    case .outsideActiveWindow: "The check occurred outside the active window."
    case .dailyLimit: "Today's maximum scare count had been reached."
    case .cooldown: "The global cooldown was still active."
    case .chanceNotSelected: "The random-chance check did not select a scare."
    case .asleepOrLocked: "The Mac was asleep or the session was locked."
    case .screenCapture: "Screen recording or Apple screen sharing was active."
    case .fullScreenApp: "A full-screen app was active."
    case .cameraOrMicrophone: "Camera or microphone use was detectable."
    case .externalDisplay: "An external display was connected."
    case .lowBattery: "Battery level was below the configured safety limit."
    case .highVolume: "System volume was above the configured safety limit."
    case .idleReturnGracePeriod: "The return-from-idle grace period was active."
    case .excludedApplication:
      if let context {
        "\(context) was the frontmost excluded app."
      } else {
        "An excluded app was frontmost."
      }
    case .noAvailableVideo: "No enabled video was available."
    case .noEligibleVideo: "Every enabled video was temporarily cooling down."
    case .presentationCancelled: "The presentation became ineligible before playback."
    case .playbackFailed: "Playback could not be completed."
    }
  }

  fileprivate var systemImage: String {
    switch kind {
    case .played: "play.circle.fill"
    case .skipped: "forward.circle.fill"
    case .dismissed: "xmark.circle.fill"
    case .failed: "exclamationmark.triangle.fill"
    }
  }

  fileprivate var tint: Color {
    switch kind {
    case .played: .green
    case .skipped: .secondary
    case .dismissed: .orange
    case .failed: .red
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
