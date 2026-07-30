import StartleCore
import SwiftUI

struct OnboardingView: View {
  @Environment(AppState.self) private var state
  @State private var page = 0
  private let pageCount = 5

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        LinearGradient(
          colors: [Color.orange.opacity(0.16), Color.purple.opacity(0.08), .clear],
          startPoint: .topLeading, endPoint: .bottomTrailing)
        Group {
          switch page {
          case 0:
            onboardingPage(
              icon: "eye.fill", title: "Welcome to Startle",
              text:
                "Startle waits quietly in your menu bar, then plays one of your videos at an unpredictable time. You remain in control."
            )
          case 1:
            onboardingPage(
              icon: "clock.badge.questionmark", title: "Random, within your rules",
              text:
                "Choose random or fixed intervals, chance-based checks, active hours, cooldowns, and daily limits. Sleep and wake never cause an immediate overdue scare."
            )
          case 2:
            onboardingPage(
              icon: "shield.checkered", title: "Know the brakes",
              text:
                "Press Escape to close any scare. Press ⌘⌥⇧ Esc anywhere to dismiss and disable Startle. Safety settings can also pause around screen capture, full-screen apps, displays, battery, and volume."
            )
          case 3: warningPage
          default: importPage
          }
        }.padding(60)
      }
      Divider()
      HStack {
        Text("\(page + 1) of \(pageCount)").foregroundStyle(.secondary)
        Spacer()
        if page > 0 { Button("Back") { withAnimation { page -= 1 } } }
        if page < pageCount - 1 {
          Button("Continue") { withAnimation { page += 1 } }.buttonStyle(.borderedProminent)
        } else {
          Button(state.library.enabledVideos.isEmpty ? "Finish Without a Video" : "Finish Setup") {
            finishSetup()
          }.buttonStyle(.borderedProminent)
        }
      }.padding(20)
    }.frame(minWidth: 800, minHeight: 560)
  }

  private func onboardingPage(icon: String, title: String, text: String) -> some View {
    VStack(spacing: 22) {
      Image(systemName: icon).font(.system(size: 68, weight: .medium)).foregroundStyle(.orange)
      Text(title).font(.system(size: 34, weight: .bold))
      Text(text).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(
        maxWidth: 600)
    }
  }

  private var warningPage: some View {
    VStack(spacing: 20) {
      Image(systemName: "heart.slash.fill").font(.system(size: 64)).foregroundStyle(.red)
      Text("Not for everyone").font(.system(size: 34, weight: .bold))
      Text(
        "Do not use Startle on people with heart conditions, epilepsy, severe anxiety, PTSD, or sound sensitivity. Get consent. Never use it where a sudden reaction could cause harm."
      ).font(.title3).multilineTextAlignment(.center).frame(maxWidth: 620)
      Text(
        "Startle uses no private APIs. Choosing videos grants access only to those files; some automatic safety signals are limited by macOS privacy protections."
      ).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 580)
    }
  }

  private var importPage: some View {
    VStack(spacing: 20) {
      Image(systemName: hasAvailableVideo ? "checkmark.circle.fill" : "film.stack")
        .font(.system(size: 64))
        .foregroundStyle(hasAvailableVideo ? .green : .orange)
      Text(hasAvailableVideo ? "Ready when you are" : "Import your first video")
        .font(.system(size: 34, weight: .bold))
      Text(
        importMessage
      ).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 580)
      Button("Choose Video…") { state.chooseVideos() }.buttonStyle(.borderedProminent).controlSize(
        .large)
      if hasAvailableVideo {
        Label(
          "\(state.library.enabledVideos.count) available video\(state.library.enabledVideos.count == 1 ? "" : "s")",
          systemImage: "checkmark.seal.fill"
        ).foregroundStyle(.green)
      } else if !state.library.videos.isEmpty {
        Label(
          "\(state.library.videos.count) saved video\(state.library.videos.count == 1 ? " needs" : "s need") relinking",
          systemImage: "exclamationmark.triangle.fill"
        ).foregroundStyle(.orange)
      }
    }
  }

  private var hasAvailableVideo: Bool { !state.library.enabledVideos.isEmpty }

  private var importMessage: String {
    if hasAvailableVideo {
      return
        "Your video is stored as a secure bookmark. Finish setup, review the schedule, then enable Startle from the Dashboard."
    }
    if state.library.videos.isEmpty {
      return
        "You can add a video now or finish setup and import one later. Startle stays disabled until an enabled video is available."
    }
    return
      "Your saved videos are unavailable. Finish setup and relink them from Videos, or choose a new file now. Startle stays disabled in the meantime."
  }

  private func finishSetup() {
    state.settings.values.onboardingCompleted = true
    state.setEnabled(false)
  }
}
