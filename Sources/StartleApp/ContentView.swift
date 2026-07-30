import StartleCore
import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
  case dashboard, videos, schedule, safety, appearance, about
  var id: Self { self }
  var title: String { rawValue.capitalized }
  var icon: String {
    switch self {
    case .dashboard: "sparkles"
    case .videos: "play.rectangle.on.rectangle"
    case .schedule: "clock.badge.questionmark"
    case .safety: "shield.lefthalf.filled"
    case .appearance: "paintbrush"
    case .about: "info.circle"
    }
  }
}

struct ContentView: View {
  @Environment(AppState.self) private var state
  @State private var selection: SidebarSection? = .dashboard

  var body: some View {
    Group {
      if !state.settings.values.onboardingCompleted {
        OnboardingView()
      } else {
        NavigationSplitView {
          List(SidebarSection.allCases, selection: $selection) { section in
            Label(section.title, systemImage: section.icon).tag(section)
          }
          .navigationSplitViewColumnWidth(min: 180, ideal: 205)
        } detail: {
          sectionView(selection ?? .dashboard)
        }
      }
    }
    .alert(
      "Startle Needs Attention",
      isPresented: Binding(
        get: { state.combinedError != nil }, set: { if !$0 { state.clearError() } })
    ) {
      Button("OK") { state.clearError() }
    } message: {
      Text(state.combinedError ?? "Unknown error")
    }
    .onChange(of: state.settings.values.schedule) { state.scheduleChanged() }
    .onChange(of: state.settings.values.safety) { state.scheduleChanged() }
  }

  @ViewBuilder private func sectionView(_ section: SidebarSection) -> some View {
    switch section {
    case .dashboard: DashboardView()
    case .videos: VideosView()
    case .schedule: ScheduleView()
    case .safety: SafetyView()
    case .appearance: AppearanceView()
    case .about: AboutView()
    }
  }
}

struct Page<Content: View>: View {
  let title: String
  let subtitle: String
  @ViewBuilder var content: Content
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 5) {
          Text(title).font(.largeTitle.bold())
          Text(subtitle).foregroundStyle(.secondary)
        }
        content
      }.padding(24).frame(maxWidth: 920, alignment: .leading)
    }.navigationTitle(title)
  }
}
