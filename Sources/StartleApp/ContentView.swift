import AppKit
import StartleCore
import SwiftUI
import UniformTypeIdentifiers

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
        .alert("Startle Needs Attention", isPresented: Binding(get: { state.combinedError != nil }, set: { if !$0 { state.clearError() } })) {
            Button("OK") { state.clearError() }
        } message: { Text(state.combinedError ?? "Unknown error") }
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

private struct Page<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.largeTitle.bold())
                    Text(subtitle).foregroundStyle(.secondary)
                }
                content
            }.padding(30).frame(maxWidth: 920, alignment: .leading)
        }.navigationTitle(title)
    }
}

private struct DashboardView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        Page(title: "Dashboard", subtitle: "A calm overview of future chaos.") {
            HStack(spacing: 16) {
                StatusCard(title: "Status", value: state.settings.values.scaresEnabled ? "Armed" : "Disabled", icon: state.settings.values.scaresEnabled ? "bolt.fill" : "pause.fill", tint: state.settings.values.scaresEnabled ? .orange : .secondary)
                StatusCard(title: "Next scare", value: state.scheduler.nextWindowDescription, icon: "clock", tint: .purple)
                StatusCard(title: "Today", value: "\(state.settings.scaresToday())", icon: "calendar", tint: .blue)
                StatusCard(title: "All time", value: "\(state.settings.values.totalScareCount)", icon: "number", tint: .pink)
            }
            GroupBox {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Scares").font(.headline)
                        Text(state.settings.values.scaresEnabled ? "Startle is waiting in the background." : "Nothing will play until you enable Startle.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { state.settings.values.scaresEnabled }, set: state.setEnabled)).labelsHidden().toggleStyle(.switch)
                }.padding(8)
            }
            HStack {
                Button("Test Jumpscare", systemImage: "play.fill") { state.testScare() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(state.library.enabledVideos.isEmpty)
                Button("Pause for 1 Hour", systemImage: "cup.and.saucer") { state.pauseOneHour() }.controlSize(.large).disabled(!state.settings.values.scaresEnabled)
            }
            if let pause = state.settings.values.pauseUntil, pause > Date() {
                Label("Paused until \(pause.formatted(date: .omitted, time: .shortened))", systemImage: "moon.zzz.fill").foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatusCard: View {
    let title: String, value: String, icon: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(tint)
            Text(value).font(.title3.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.75)
        }.padding(16).frame(maxWidth: .infinity, minHeight: 110, alignment: .leading).background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct VideosView: View {
    @Environment(AppState.self) private var state
    @State private var dropTargeted = false
    var body: some View {
        Page(title: "Videos", subtitle: "Import local MP4, MOV, or M4V files. Startle stores secure access—not copies.") {
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 34)).foregroundStyle(.orange)
                Text("Drop jumpscare videos here").font(.headline)
                Text("or choose files from your Mac").foregroundStyle(.secondary)
                Button("Import Videos…") { state.chooseVideos() }.buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 155)
            .background(dropTargeted ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(dropTargeted ? Color.accentColor : .secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [7])))
            .onDrop(of: [UTType.fileURL.identifier, UTType.movie.identifier], isTargeted: $dropTargeted) { providers in
                for provider in providers { provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) } ?? (item as? URL)
                    if let url { Task { @MainActor in state.importVideos([url]) } }
                }}
                return true
            }
            if state.library.videos.isEmpty {
                ContentUnavailableView("No Videos Yet", systemImage: "film", description: Text("Import at least one video to enable scares."))
            } else {
                LazyVStack(spacing: 10) { ForEach(state.library.videos) { VideoRow(item: $0) } }
            }
        }
    }
}

private struct VideoRow: View {
    @Environment(AppState.self) private var state
    let item: VideoItem
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(.black)
                if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFill() }
                else { Image(systemName: item.isMissing ? "exclamationmark.triangle" : "film").foregroundStyle(item.isMissing ? .red : .secondary) }
            }.frame(width: 142, height: 80).clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 7) {
                HStack { Text(item.displayName).font(.headline); if item.isMissing { Text("Missing").font(.caption.bold()).foregroundStyle(.red) } }
                Text(duration(item.duration)).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Toggle("Enabled", isOn: binding(\.isEnabled)).toggleStyle(.switch).disabled(item.isMissing)
                    Text("Volume").font(.caption)
                    Slider(value: binding(\.volume), in: 0...1).frame(width: 100)
                    TextField("Start", value: binding(\.trimStart), format: .number.precision(.fractionLength(1))).frame(width: 52)
                    Text("to").foregroundStyle(.secondary)
                    TextField("End", value: optionalEndBinding, format: .number.precision(.fractionLength(1))).frame(width: 58)
                }.controlSize(.small)
            }
            Spacer()
            Button("Preview", systemImage: "play.circle") { state.testScare(video: item) }.disabled(item.isMissing)
            Button(role: .destructive) { state.removeVideo(item) } label: { Image(systemName: "trash") }.help("Remove video")
        }.padding(12).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 13)).task { thumbnail = await state.library.thumbnail(for: item) }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<VideoItem, T>) -> Binding<T> {
        Binding(get: { item[keyPath: keyPath] }, set: { value in
            var copy = item; copy[keyPath: keyPath] = value; state.library.update(copy)
            if state.library.enabledVideos.isEmpty { state.setEnabled(false) }
        })
    }
    private var optionalEndBinding: Binding<Double> {
        Binding(get: { item.trimEnd ?? item.duration }, set: { value in var copy = item; copy.trimEnd = value >= item.duration ? nil : max(copy.trimStart, value); state.library.update(copy) })
    }
    private func duration(_ seconds: Double) -> String { Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)) }
}

private struct ScheduleView: View {
    @Environment(AppState.self) private var state
    private let intervals: [(String, TimeInterval)] = [("5 min", 300), ("15 min", 900), ("30 min", 1800), ("1 hr", 3600), ("2 hr", 7200), ("4 hr", 14400)]

    var body: some View {
        @Bindable var store = state.settings
        Page(title: "Schedule", subtitle: "Choose when Startle may surprise you. Every change replaces the pending timer.") {
            GroupBox("Timing mode") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Mode", selection: $store.values.schedule.mode) { ForEach(ScheduleMode.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    switch store.values.schedule.mode {
                    case .randomInterval:
                        IntervalPicker(title: "Minimum interval", selection: $store.values.schedule.minimumInterval, choices: intervals)
                        IntervalPicker(title: "Maximum interval", selection: $store.values.schedule.maximumInterval, choices: intervals)
                        if store.values.schedule.minimumInterval > store.values.schedule.maximumInterval { Label("Startle will automatically use the two values in ascending order.", systemImage: "arrow.up.arrow.down").font(.caption).foregroundStyle(.secondary) }
                    case .fixedInterval:
                        IntervalPicker(title: "Fixed interval", selection: $store.values.schedule.fixedInterval, choices: intervals)
                    case .randomChance:
                        IntervalPicker(title: "Check every", selection: $store.values.schedule.chanceCheckInterval, choices: Array(intervals.prefix(4)))
                        HStack { Text("Chance at each check"); Slider(value: $store.values.schedule.chancePercent, in: 1...100, step: 1); Text("\(Int(store.values.schedule.chancePercent))%").monospacedDigit().frame(width: 42) }
                    }
                }.padding(8)
            }
            GroupBox("Active window") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) { ForEach(Array(Calendar.current.shortWeekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                        let day = index + 1
                        Toggle(symbol, isOn: Binding(get: { store.values.schedule.activeDays.contains(day) }, set: { enabled in
                            if enabled { store.values.schedule.activeDays.insert(day) } else { store.values.schedule.activeDays.remove(day) }
                        })).toggleStyle(.button)
                    }}
                    HStack {
                        DatePicker("From", selection: minutesBinding($store.values.schedule.activeStartMinutes), displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: minutesBinding($store.values.schedule.activeEndMinutes), displayedComponents: .hourAndMinute)
                    }
                }.padding(8)
            }
            GroupBox("Limits") {
                VStack(alignment: .leading, spacing: 14) {
                    IntervalPicker(title: "Cooldown after a scare", selection: $store.values.schedule.cooldown, choices: [("None", 0)] + intervals)
                    Stepper("Maximum scares per day: \(store.values.schedule.maximumScaresPerDay)", value: $store.values.schedule.maximumScaresPerDay, in: 1...50)
                    Toggle("Wait after I return from keyboard or mouse inactivity", isOn: $store.values.schedule.avoidAfterIdle)
                    if store.values.schedule.avoidAfterIdle { IntervalPicker(title: "Return grace period", selection: $store.values.schedule.idleGracePeriod, choices: [("1 min", 60), ("5 min", 300), ("10 min", 600), ("15 min", 900)]) }
                }.padding(8)
            }
        }
    }

    private func minutesBinding(_ value: Binding<Int>) -> Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: value.wrappedValue / 60, minute: value.wrappedValue % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in value.wrappedValue = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date) })
    }
}

private struct IntervalPicker: View {
    let title: String
    @Binding var selection: TimeInterval
    let choices: [(String, TimeInterval)]
    var body: some View {
        Picker(title, selection: $selection) { ForEach(choices, id: \.1) { Text($0.0).tag($0.1) } }.frame(maxWidth: 360)
    }
}

private struct SafetyView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        @Bindable var store = state.settings
        Page(title: "Safety", subtitle: "Strong brakes are part of the prank.") {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "heart.slash.fill").font(.title).foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Health warning").font(.headline)
                    Text("Do not use Startle on anyone with a heart condition, epilepsy, severe anxiety, PTSD, or sound sensitivity. Get clear consent and never use it where a sudden reaction could cause injury.")
                }
            }.padding(16).background(Color.red.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))

            GroupBox("Emergency controls") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Master emergency disable") { Text("⌘⌥⇧ Esc").font(.system(.body, design: .monospaced).bold()).padding(.horizontal, 10).padding(.vertical, 5).background(.quaternary, in: RoundedRectangle(cornerRadius: 6)) }
                    Label("Escape always closes the active scare immediately.", systemImage: "escape")
                    Button("Disable Now", role: .destructive) { state.emergencyDisable() }
                }.padding(8)
            }

            GroupBox("Automatic pauses") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Pause while camera or microphone use is detectable", isOn: $store.values.safety.pauseForCameraOrMicrophone)
                    Toggle("Pause during screen recording or screen sharing", isOn: $store.values.safety.pauseForScreenCapture)
                    Toggle("Pause over full-screen games, presentations, or videos", isOn: $store.values.safety.pauseForFullScreenApps)
                    Toggle("Pause during Focus / Do Not Disturb when detectable", isOn: $store.values.safety.pauseForFocus)
                    Divider()
                    Label("Startle uses public device-running signals for camera and microphone activity, plus supported app signals for Apple screen capture. Focus status and third-party sharing may be undetectable; no private APIs are used.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }

            GroupBox("Environment limits") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Disable when an external display is connected", isOn: $store.values.safety.disableWithExternalDisplay)
                    HStack { Text("Disable below battery"); Slider(value: $store.values.safety.disableBelowBatteryPercent, in: 0...50, step: 5); Text("\(Int(store.values.safety.disableBelowBatteryPercent))%").monospacedDigit().frame(width: 38) }
                    HStack { Text("Disable above system volume"); Slider(value: $store.values.safety.disableAboveSystemVolumePercent, in: 10...100, step: 5); Text("\(Int(store.values.safety.disableAboveSystemVolumePercent))%").monospacedDigit().frame(width: 38) }
                    Toggle("Quiet mode (play without sound)", isOn: $store.values.safety.quietMode)
                    Picker("Accessibility countdown", selection: $store.values.safety.countdownSeconds) {
                        Text("Off").tag(0); Text("3 seconds").tag(3); Text("5 seconds").tag(5); Text("10 seconds").tag(10)
                    }.frame(maxWidth: 360)
                }.padding(8)
            }

            GroupBox("Login") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Never run Startle at login", isOn: $store.values.safety.neverRunAtLogin)
                        .onChange(of: store.values.safety.neverRunAtLogin) { _, forbidden in if forbidden { state.launchAtLogin.setEnabled(false, forbidden: false) } }
                    Toggle("Launch at login", isOn: Binding(get: { state.launchAtLogin.isEnabled }, set: { state.launchAtLogin.setEnabled($0, forbidden: store.values.safety.neverRunAtLogin) }))
                        .disabled(store.values.safety.neverRunAtLogin)
                }.padding(8)
            }
        }
    }
}

private struct AppearanceView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        @Bindable var store = state.settings
        Page(title: "Appearance", subtitle: "Tune how Startle looks before—and during—the surprise.") {
            GroupBox("App") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Theme", selection: $store.values.appearance.theme) { ForEach(AppTheme.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    Picker("Menu bar icon", selection: $store.values.appearance.menuBarIcon) { ForEach(MenuBarIconStyle.allCases, id: \.self) { Label($0.title, systemImage: $0.symbolName).tag($0) } }.frame(maxWidth: 360)
                }.padding(8)
            }
            GroupBox("Scare display") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Display mode", selection: $store.values.appearance.displayMode) { ForEach(ScareDisplayMode.allCases, id: \.self) { Text($0.title).tag($0) } }.frame(maxWidth: 420)
                    ColorPicker("Loading background", selection: hexColorBinding($store.values.appearance.backgroundHex), supportsOpacity: false)
                    Toggle("Crop video to fill", isOn: $store.values.appearance.cropToFill)
                    Toggle("Hide cursor during playback", isOn: $store.values.appearance.hideCursor)
                }.padding(8)
            }
        }
    }

    private func hexColorBinding(_ value: Binding<String>) -> Binding<Color> {
        Binding(get: { Color(hex: value.wrappedValue) }, set: { color in
            if let components = NSColor(color).usingColorSpace(.deviceRGB) {
                value.wrappedValue = String(format: "%02X%02X%02X", Int(components.redComponent * 255), Int(components.greenComponent * 255), Int(components.blueComponent * 255))
            }
        })
    }
}

private extension Color {
    init(hex: String) {
        let value = Int(hex, radix: 16) ?? 0x09090B
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

private struct AboutView: View {
    var body: some View {
        Page(title: "About", subtitle: "A tiny utility with an outsized sense of timing.") {
            VStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 112, height: 112)
                Text("Startle").font(.largeTitle.bold())
                Text("Version 1.0").foregroundStyle(.secondary)
                Text("Native SwiftUI • AVFoundation playback • privacy-minded local storage").foregroundStyle(.secondary)
                Divider().frame(width: 380)
                Text("Startle never uploads your videos. Imported files remain where you put them and are reopened through security-scoped bookmarks.").multilineTextAlignment(.center).frame(maxWidth: 520)
            }.frame(maxWidth: .infinity).padding(.vertical, 40)
        }
    }
}

private struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @State private var page = 0
    private let pageCount = 5

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color.orange.opacity(0.16), Color.purple.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                Group {
                    switch page {
                    case 0: onboardingPage(icon: "eye.fill", title: "Welcome to Startle", text: "Startle waits quietly in your menu bar, then plays one of your videos at an unpredictable time. You remain in control.")
                    case 1: onboardingPage(icon: "clock.badge.questionmark", title: "Random, within your rules", text: "Choose random or fixed intervals, chance-based checks, active hours, cooldowns, and daily limits. Sleep and wake never cause an immediate overdue scare.")
                    case 2: onboardingPage(icon: "shield.checkered", title: "Know the brakes", text: "Press Escape to close any scare. Press ⌘⌥⇧ Esc anywhere to dismiss and disable Startle. Safety settings can also pause around screen capture, full-screen apps, displays, battery, and volume.")
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
                if page < pageCount - 1 { Button("Continue") { withAnimation { page += 1 } }.buttonStyle(.borderedProminent) }
                else { Button("Finish Setup") { state.settings.values.onboardingCompleted = true; state.setEnabled(false) }.buttonStyle(.borderedProminent).disabled(state.library.enabledVideos.isEmpty) }
            }.padding(20)
        }.frame(minWidth: 800, minHeight: 560)
    }

    private func onboardingPage(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 22) {
            Image(systemName: icon).font(.system(size: 68, weight: .medium)).foregroundStyle(.orange)
            Text(title).font(.system(size: 34, weight: .bold))
            Text(text).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 600)
        }
    }

    private var warningPage: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.slash.fill").font(.system(size: 64)).foregroundStyle(.red)
            Text("Not for everyone").font(.system(size: 34, weight: .bold))
            Text("Do not use Startle on people with heart conditions, epilepsy, severe anxiety, PTSD, or sound sensitivity. Get consent. Never use it where a sudden reaction could cause harm.").font(.title3).multilineTextAlignment(.center).frame(maxWidth: 620)
            Text("Startle uses no private APIs. Choosing videos grants access only to those files; some automatic safety signals are limited by macOS privacy protections.").foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 580)
        }
    }

    private var importPage: some View {
        VStack(spacing: 20) {
            Image(systemName: state.library.videos.isEmpty ? "film.stack" : "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(state.library.videos.isEmpty ? .orange : .green)
            Text(state.library.videos.isEmpty ? "Import your first video" : "Ready when you are").font(.system(size: 34, weight: .bold))
            Text(state.library.videos.isEmpty ? "Startle stays disabled until setup is complete and at least one video is available." : "Your video is stored as a secure bookmark. Finish setup, review the schedule, then enable Startle from the Dashboard.").foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 580)
            Button("Choose Video…") { state.chooseVideos() }.buttonStyle(.borderedProminent).controlSize(.large)
            if !state.library.videos.isEmpty { Label("\(state.library.videos.count) video\(state.library.videos.count == 1 ? "" : "s") imported", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
        }
    }
}
