import AppKit
import StartleCore
import SwiftUI
import UniformTypeIdentifiers

struct VideosView: View {
  @Environment(AppState.self) private var state
  @State private var dropTargeted = false
  @State private var filter: VideoFilter = .all
  @State private var selectedID: VideoItem.ID?
  @State private var confirmRemoveMissing = false

  private var visibleVideos: [VideoItem] {
    switch filter {
    case .all: state.library.videos
    case .available: state.library.videos.filter { !$0.isMissing }
    case .missing: state.library.videos.filter(\.isMissing)
    }
  }

  private var selectedVideo: VideoItem? {
    state.library.videos.first { $0.id == selectedID }
  }

  var body: some View {
    Page(
      title: "Videos",
      subtitle: "Import local MP4, MOV, or M4V files. Startle stores secure access—not copies."
    ) {
      importDropZone
      if state.library.videos.isEmpty {
        ContentUnavailableView(
          "No Videos Yet", systemImage: "film",
          description: Text("Import at least one video to enable scares."))
      } else {
        selectionControls
        libraryToolbar
        videoList
        if let selectedVideo {
          VideoInspector(item: selectedVideo)
        } else {
          ContentUnavailableView(
            "Select a Video", systemImage: "sidebar.left",
            description: Text("Choose a video above to edit playback and trim settings."))
        }
      }
    }
    .onAppear { repairSelection() }
    .onChange(of: state.library.videos.map(\.id)) { _, _ in repairSelection() }
    .onChange(of: filter) { _, _ in repairSelection() }
    .confirmationDialog(
      "Remove every missing video?", isPresented: $confirmRemoveMissing,
      titleVisibility: .visible
    ) {
      Button("Remove Missing Videos", role: .destructive) {
        state.removeMissingVideos()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This removes missing entries and their saved playback settings. Video files are never deleted."
      )
    }
  }

  private var selectionControls: some View {
    GroupBox("Shuffle") {
      VStack(alignment: .leading, spacing: 12) {
        LabeledContent("Mode") {
          Picker("Shuffle mode", selection: selectionModeBinding) {
            ForEach(VideoSelectionMode.allCases, id: \.self) { mode in
              Text(mode.title).tag(mode)
            }
          }
          .labelsHidden()
          .frame(maxWidth: 280)
        }
        Stepper(
          "Avoid the last \(state.library.selectionSettings.recentHistoryCount) videos",
          value: recentHistoryBinding, in: 3...5)
        Text(selectionModeDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(8)
    }
  }

  private var selectionModeBinding: Binding<VideoSelectionMode> {
    Binding(
      get: { state.library.selectionSettings.mode },
      set: { mode in
        var settings = state.library.selectionSettings
        settings.mode = mode
        state.library.updateSelectionSettings(settings)
      })
  }

  private var recentHistoryBinding: Binding<Int> {
    Binding(
      get: { state.library.selectionSettings.recentHistoryCount },
      set: { count in
        var settings = state.library.selectionSettings
        settings.recentHistoryCount = count
        state.library.updateSelectionSettings(settings)
      })
  }

  private var selectionModeDescription: String {
    switch state.library.selectionSettings.mode {
    case .weightedRandom:
      "Frequency, rare-video probability, cooldowns, and recent history shape each selection."
    case .shuffleBag:
      "Every enabled video plays once per cycle. Cooldowns and recent history still apply; frequency and rare settings do not."
    }
  }

  private var importDropZone: some View {
    VStack(spacing: 9) {
      Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 30))
        .foregroundStyle(.orange)
      Text("Drop jumpscare videos here").font(.headline)
      Text("or choose files from your Mac").foregroundStyle(.secondary)
      Button("Import Videos…") { state.chooseVideos() }.buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, minHeight: 135)
    .background(
      dropTargeted ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.07),
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16).stroke(
        dropTargeted ? Color.accentColor : .secondary.opacity(0.3),
        style: StrokeStyle(lineWidth: 1.5, dash: [7]))
    )
    .onDrop(of: [UTType.fileURL.identifier, UTType.movie.identifier], isTargeted: $dropTargeted) {
      providers in
      for provider in providers {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
          let url =
            (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            ?? (item as? URL)
          guard let url else { return }
          let securityScoped = url.startAccessingSecurityScopedResource()
          Task { @MainActor in
            await state.importVideosNow([url])
            if securityScoped { url.stopAccessingSecurityScopedResource() }
          }
        }
      }
      return true
    }
  }

  private var libraryToolbar: some View {
    HStack(spacing: 12) {
      Picker("Video filter", selection: $filter) {
        ForEach(VideoFilter.allCases) { option in
          Text(option.title).tag(option)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(width: 270)
      .accessibilityLabel("Video filter")

      Spacer()

      Text("\(state.library.videos.count) total")
        .font(.caption)
        .foregroundStyle(.secondary)

      Menu("Bulk Actions", systemImage: "ellipsis.circle") {
        Button("Enable All Available Videos") { state.setAllVideosEnabled(true) }
          .disabled(state.library.videos.allSatisfy { $0.isMissing || $0.isEnabled })
        Button("Disable All Videos") { state.setAllVideosEnabled(false) }
          .disabled(state.library.videos.allSatisfy { !$0.isEnabled })
        Divider()
        Button("Remove Missing Videos…", role: .destructive) {
          confirmRemoveMissing = true
        }
        .disabled(!state.library.videos.contains(where: \.isMissing))
      }
    }
  }

  @ViewBuilder private var videoList: some View {
    if visibleVideos.isEmpty {
      ContentUnavailableView(
        filter.emptyTitle, systemImage: filter.emptyIcon,
        description: Text(filter.emptyDescription)
      )
      .frame(minHeight: 180)
    } else {
      LazyVStack(spacing: 0) {
        ForEach(Array(visibleVideos.enumerated()), id: \.element.id) { index, item in
          VideoSummaryRow(item: item, isSelected: selectedID == item.id) {
            selectedID = item.id
          }
          if index < visibleVideos.count - 1 {
            Divider().padding(.leading, 112)
          }
        }
      }
      .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 13))
      .clipShape(RoundedRectangle(cornerRadius: 13))
    }
  }

  private func repairSelection() {
    if let selectedID, visibleVideos.contains(where: { $0.id == selectedID }) { return }
    selectedID = visibleVideos.first?.id
  }
}

private enum VideoFilter: String, CaseIterable, Identifiable {
  case all, available, missing

  var id: Self { self }
  var title: String {
    switch self {
    case .all: "All"
    case .available: "Available"
    case .missing: "Missing"
    }
  }
  var emptyTitle: String {
    switch self {
    case .all: "No Videos Yet"
    case .available: "No Available Videos"
    case .missing: "No Missing Videos"
    }
  }
  var emptyIcon: String {
    switch self {
    case .all: "film"
    case .available: "film.stack"
    case .missing: "checkmark.circle"
    }
  }
  var emptyDescription: String {
    switch self {
    case .all: "Import a video to get started."
    case .available: "Relink a missing file or import another video."
    case .missing: "Every saved video is available."
    }
  }
}

private struct VideoSummaryRow: View {
  @Environment(AppState.self) private var state
  let item: VideoItem
  let isSelected: Bool
  let onSelect: () -> Void
  @State private var thumbnail: NSImage?

  var body: some View {
    HStack(spacing: 12) {
      Button(action: onSelect) {
        HStack(spacing: 12) {
          thumbnailView
          VStack(alignment: .leading, spacing: 4) {
            Text(item.displayName)
              .font(.headline)
              .lineLimit(1)
              .truncationMode(.middle)
            HStack(spacing: 8) {
              Text(duration(item.duration))
              if item.isMissing {
                Label("Missing", systemImage: "exclamationmark.triangle.fill")
                  .foregroundStyle(.red)
              }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        "\(item.displayName), \(duration(item.duration))\(item.isMissing ? ", missing" : "")"
      )
      Spacer(minLength: 12)
      if item.isMissing {
        Button("Relink…", systemImage: "arrow.triangle.2.circlepath") {
          state.chooseReplacement(for: item)
        }
        .buttonStyle(.borderless)
      }
      Toggle("Enable \(item.displayName)", isOn: binding(\.isEnabled))
        .labelsHidden()
        .toggleStyle(.switch)
        .disabled(item.isMissing)
        .accessibilityLabel("Enable \(item.displayName)")
    }
    .padding(10)
    .background(isSelected ? Color.accentColor.opacity(0.14) : .clear)
    .task(id: item.lastKnownPath) { thumbnail = await state.library.thumbnail(for: item) }
  }

  private var thumbnailView: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 7).fill(.black)
      if let thumbnail {
        Image(nsImage: thumbnail).resizable().scaledToFill()
      } else {
        Image(systemName: item.isMissing ? "exclamationmark.triangle" : "film")
          .foregroundStyle(item.isMissing ? .red : .secondary)
      }
    }
    .frame(width: 88, height: 50)
    .clipShape(RoundedRectangle(cornerRadius: 7))
    .accessibilityHidden(true)
  }

  private func binding<T>(_ keyPath: WritableKeyPath<VideoItem, T>) -> Binding<T> {
    Binding(
      get: { item[keyPath: keyPath] },
      set: { value in
        var copy = item
        copy[keyPath: keyPath] = value
        state.library.update(copy)
        if state.library.enabledVideos.isEmpty { state.setEnabled(false) }
      })
  }

  private func duration(_ seconds: Double) -> String {
    Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
  }
}

private struct VideoInspector: View {
  @Environment(AppState.self) private var state
  let item: VideoItem
  @State private var thumbnail: NSImage?
  @State private var confirmRemoval = false

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .top, spacing: 16) {
          inspectorThumbnail
          VStack(alignment: .leading, spacing: 6) {
            Text(item.displayName).font(.title3.bold()).textSelection(.enabled)
            Text(duration(item.duration)).foregroundStyle(.secondary)
            if item.isMissing {
              Label(
                "This file moved or is unavailable. Relink it to keep these settings.",
                systemImage: "exclamationmark.triangle.fill"
              )
              .foregroundStyle(.red)
              .fixedSize(horizontal: false, vertical: true)
            }
          }
          Spacer()
        }

        Divider()

        VStack(alignment: .leading, spacing: 14) {
          LabeledContent("Enabled") {
            Toggle("Enable \(item.displayName)", isOn: binding(\.isEnabled))
              .labelsHidden()
              .toggleStyle(.switch)
              .accessibilityLabel("Enable \(item.displayName)")
          }
          LabeledContent("Volume") {
            HStack {
              Slider(value: binding(\.volume), in: 0...1) {
                Text("Playback volume")
              }
              .labelsHidden()
              .accessibilityLabel("Playback volume")
              Text("\(Int(item.volume * 100))%")
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
            }
            .frame(maxWidth: 360)
          }
          LabeledContent("Frequency weight") {
            HStack {
              Slider(value: binding(\.selectionWeight), in: 0.1...10, step: 0.1) {
                Text("Selection frequency weight")
              }
              .labelsHidden()
              .accessibilityLabel("Selection frequency weight")
              Text(item.selectionWeight.formatted(.number.precision(.fractionLength(1))))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
            }
            .frame(maxWidth: 360)
          }
          LabeledContent("Rare") {
            Toggle("Play this video rarely", isOn: binding(\.isRare))
              .toggleStyle(.switch)
              .help("Rare videos receive 10% of their configured frequency weight.")
          }
          LabeledContent("Video cooldown") {
            Picker("Video cooldown", selection: binding(\.selectionCooldown)) {
              Text("None").tag(TimeInterval(0))
              Text("30 min").tag(TimeInterval(30 * 60))
              Text("1 hr").tag(TimeInterval(60 * 60))
              Text("2 hr").tag(TimeInterval(2 * 60 * 60))
              Text("4 hr").tag(TimeInterval(4 * 60 * 60))
              Text("8 hr").tag(TimeInterval(8 * 60 * 60))
              Text("24 hr").tag(TimeInterval(24 * 60 * 60))
            }
            .labelsHidden()
            .frame(maxWidth: 220)
          }
          LabeledContent("Trim") {
            HStack(spacing: 8) {
              TextField(
                "Start", value: trimStartBinding,
                format: .number.precision(.fractionLength(1))
              )
              .frame(width: 72)
              .accessibilityLabel("Trim start in seconds")
              Text("to").foregroundStyle(.secondary)
              TextField(
                "End", value: optionalEndBinding,
                format: .number.precision(.fractionLength(1))
              )
              .frame(width: 72)
              .accessibilityLabel("Trim end in seconds")
              Text("seconds").foregroundStyle(.secondary)
            }
          }
        }
        .disabled(item.isMissing)

        HStack {
          if item.isMissing {
            Button("Relink File…", systemImage: "arrow.triangle.2.circlepath") {
              state.chooseReplacement(for: item)
            }
            .buttonStyle(.borderedProminent)
          } else {
            Button("Preview", systemImage: "play.circle") { state.testScare(video: item) }
              .buttonStyle(.borderedProminent)
          }
          Spacer()
          Button("Remove Video…", systemImage: "trash", role: .destructive) {
            confirmRemoval = true
          }
        }
      }
      .padding(8)
    } label: {
      Text("Selected Video")
    }
    .task(id: item.lastKnownPath) { thumbnail = await state.library.thumbnail(for: item) }
    .confirmationDialog(
      "Remove \(item.displayName)?", isPresented: $confirmRemoval, titleVisibility: .visible
    ) {
      Button("Remove Video", role: .destructive) { state.removeVideo(item) }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Startle removes the saved entry and its settings. The video file stays on your Mac.")
    }
  }

  private var inspectorThumbnail: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 10).fill(.black)
      if let thumbnail {
        Image(nsImage: thumbnail).resizable().scaledToFill()
      } else {
        Image(systemName: item.isMissing ? "exclamationmark.triangle" : "film")
          .font(.title2)
          .foregroundStyle(item.isMissing ? .red : .secondary)
      }
    }
    .frame(width: 142, height: 80)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .accessibilityHidden(true)
  }

  private func binding<T>(_ keyPath: WritableKeyPath<VideoItem, T>) -> Binding<T> {
    Binding(
      get: { item[keyPath: keyPath] },
      set: { value in
        var copy = item
        copy[keyPath: keyPath] = value
        state.library.update(copy)
        if state.library.enabledVideos.isEmpty { state.setEnabled(false) }
      })
  }

  private var optionalEndBinding: Binding<Double> {
    Binding(
      get: { item.trimEnd ?? item.duration },
      set: { value in
        var copy = item
        copy.trimEnd = value >= item.duration ? nil : value
        copy.normalizePlaybackSettings()
        state.library.update(copy)
      })
  }

  private var trimStartBinding: Binding<Double> {
    Binding(
      get: { item.trimStart },
      set: { value in
        var copy = item
        copy.trimStart = value
        copy.normalizePlaybackSettings()
        state.library.update(copy)
      })
  }

  private func duration(_ seconds: Double) -> String {
    Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
  }
}
