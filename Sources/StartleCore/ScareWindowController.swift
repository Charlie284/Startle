import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import QuartzCore
import os

private final class ScarePanel: NSPanel {
  var escapeHandler: (() -> Void)?
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { escapeHandler?() } else { super.keyDown(with: event) }
  }
}

private final class PlayerSurface: NSView {
  let playerLayer = AVPlayerLayer()
  let countdownLabel = NSTextField(labelWithString: "")

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer = CALayer()
    layer?.addSublayer(playerLayer)
    countdownLabel.font = .systemFont(ofSize: 72, weight: .bold)
    countdownLabel.textColor = .white
    countdownLabel.alignment = .center
    countdownLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(countdownLabel)
    NSLayoutConstraint.activate([
      countdownLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
      countdownLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) { nil }
  override func layout() {
    super.layout()
    playerLayer.frame = bounds
  }
}

@MainActor
public final class ScareWindowController {
  private var windows: [ScarePanel] = []
  private var players: [AVPlayer] = []
  private var endObserver: NSObjectProtocol?
  private var failureObserver: NSObjectProtocol?
  private var stallObserver: NSObjectProtocol?
  private var itemStatusObservation: NSKeyValueObservation?
  private var playbackStatusObservation: NSKeyValueObservation?
  private var keyMonitor: Any?
  private var completion: CheckedContinuation<Void, Error>?
  private var playbackStartTask: Task<Void, Never>?
  private var stallWatchdogTask: Task<Void, Never>?
  private var presentationWatchdogTask: Task<Void, Never>?
  private var previousApplication: NSRunningApplication?
  private var cursorHidden = false
  private var presentationID: UUID?
  private let logger = Logger(subsystem: "com.startle.app", category: "playback")

  public init() {}

  public var isPresenting: Bool { !windows.isEmpty }

  public func present(
    video: VideoItem, url: URL, safety: SafetySettings, appearance: AppearanceSettings
  ) async throws -> Bool {
    guard !isPresenting, presentationID == nil else { return false }
    let currentPresentationID = UUID()
    presentationID = currentPresentationID
    let asset = AVURLAsset(url: url)
    let isPlayable: Bool
    do {
      isPlayable = try await asset.load(.isPlayable)
    } catch {
      guard presentationID == currentPresentationID else { return false }
      presentationID = nil
      throw error
    }
    guard presentationID == currentPresentationID else { return false }
    guard isPlayable else {
      presentationID = nil
      throw StartleError.playbackFailed("The selected movie is not playable.")
    }
    guard
      !safety.excludesApplication(
        bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    else {
      presentationID = nil
      return false
    }
    guard let fallbackScreen = NSScreen.main ?? NSScreen.screens.first else {
      presentationID = nil
      throw StartleError.playbackFailed("No active display is available.")
    }
    try await withCheckedThrowingContinuation { continuation in
      completion = continuation
      previousApplication = NSWorkspace.shared.frontmostApplication
      makeWindows(
        asset: asset, video: video, safety: safety, appearance: appearance,
        fallbackScreen: fallbackScreen)
      startPlayback(
        after: safety.countdownSeconds, quietMode: safety.quietMode,
        presentationID: currentPresentationID)
      startPresentationWatchdog(
        after: Self.presentationWatchdogInterval(
          video: video, countdownSeconds: safety.countdownSeconds),
        presentationID: currentPresentationID)
    }
    return true
  }

  public func dismiss() {
    presentationID = nil
    finish(nil)
  }

  private func makeWindows(
    asset: AVURLAsset,
    video: VideoItem,
    safety: SafetySettings,
    appearance: AppearanceSettings,
    fallbackScreen: NSScreen
  ) {
    let targetScreens: [NSScreen]
    switch appearance.displayMode {
    case .allDisplays: targetScreens = NSScreen.screens
    case .fullScreen: targetScreens = [NSScreen.main ?? fallbackScreen]
    case .centered, .currentDisplay: targetScreens = [screenUnderPointer(fallback: fallbackScreen)]
    }

    for screen in targetScreens {
      let frame: NSRect
      if appearance.displayMode == .centered {
        let size = NSSize(
          width: min(960, screen.visibleFrame.width * 0.76),
          height: min(600, screen.visibleFrame.height * 0.76))
        frame = NSRect(
          x: screen.visibleFrame.midX - size.width / 2,
          y: screen.visibleFrame.midY - size.height / 2, width: size.width, height: size.height)
      } else {
        frame = screen.frame
      }

      let panel = ScarePanel(
        contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
        defer: false, screen: screen)
      panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      panel.isOpaque = true
      panel.backgroundColor = NSColor(hex: appearance.backgroundHex) ?? .black
      panel.hidesOnDeactivate = false
      panel.escapeHandler = { [weak self] in self?.dismiss() }

      let surface = PlayerSurface(frame: frame)
      surface.layer?.backgroundColor = panel.backgroundColor.cgColor
      let item = AVPlayerItem(asset: asset)
      let trimStart = video.effectiveTrimStart
      if video.trimEnd != nil {
        item.forwardPlaybackEndTime = CMTime(
          seconds: video.effectiveTrimEnd, preferredTimescale: 600)
      }
      let player = AVPlayer(playerItem: item)
      player.volume = safety.quietMode ? 0 : Float(video.volume)
      surface.playerLayer.player = player
      surface.playerLayer.videoGravity = appearance.cropToFill ? .resizeAspectFill : .resizeAspect
      panel.contentView = surface
      panel.orderFrontRegardless()
      if trimStart > 0 {
        player.seek(
          to: CMTime(seconds: trimStart, preferredTimescale: 600), toleranceBefore: .zero,
          toleranceAfter: .zero)
      }
      windows.append(panel)
      players.append(player)
    }

    if let firstItem = players.first?.currentItem {
      endObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime, object: firstItem, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.finish(nil) }
      }
      failureObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemFailedToPlayToEndTime, object: firstItem, queue: .main
      ) { [weak self] note in
        let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        Task { @MainActor in
          self?.finish(
            StartleError.playbackFailed(error?.localizedDescription ?? "Unknown player error"))
        }
      }
      stallObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemPlaybackStalled, object: firstItem, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.startStallWatchdog() }
      }
      itemStatusObservation = firstItem.observe(\.status, options: [.new]) { [weak self] item, _ in
        guard item.status == .failed else { return }
        Task { @MainActor in
          self?.finish(
            StartleError.playbackFailed(
              item.error?.localizedDescription ?? "The player item could not be prepared."))
        }
      }
    }
    if let firstPlayer = players.first {
      playbackStatusObservation = firstPlayer.observe(\.timeControlStatus, options: [.new]) {
        [weak self] player, _ in
        guard player.timeControlStatus == .playing else { return }
        Task { @MainActor in
          self?.stallWatchdogTask?.cancel()
          self?.stallWatchdogTask = nil
        }
      }
    }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 {
        Task { @MainActor in self?.dismiss() }
        return nil
      }
      return event
    }
    NSApp.activate()
    windows.first?.makeKey()
    if appearance.hideCursor {
      NSCursor.hide()
      cursorHidden = true
    }
  }

  private func startPlayback(
    after countdownSeconds: Int, quietMode: Bool, presentationID: UUID
  ) {
    playbackStartTask?.cancel()
    playbackStartTask = Task { @MainActor [weak self] in
      guard let self else { return }
      if countdownSeconds > 0 {
        for value in stride(from: countdownSeconds, through: 1, by: -1) {
          guard self.isPresenting, self.presentationID == presentationID else { return }
          for surface in self.windows.compactMap({ $0.contentView as? PlayerSurface }) {
            surface.countdownLabel.stringValue = "\(value)"
          }
          if !quietMode { NSSound.beep() }
          do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
      }
      guard self.isPresenting, self.presentationID == presentationID else { return }
      for surface in self.windows.compactMap({ $0.contentView as? PlayerSurface }) {
        surface.countdownLabel.stringValue = ""
      }
      for player in self.players {
        player.play()
      }
    }
  }

  private func startStallWatchdog() {
    guard let currentPresentationID = presentationID else { return }
    stallWatchdogTask?.cancel()
    stallWatchdogTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(15)) } catch { return }
      guard let self, self.presentationID == currentPresentationID else { return }
      self.finish(StartleError.playbackFailed("Playback stalled and did not recover."))
    }
  }

  private func startPresentationWatchdog(after interval: TimeInterval, presentationID: UUID) {
    presentationWatchdogTask?.cancel()
    presentationWatchdogTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(max(30, interval))) } catch { return }
      guard let self, self.presentationID == presentationID else { return }
      self.finish(StartleError.playbackFailed("Playback exceeded its expected duration."))
    }
  }

  static func presentationWatchdogInterval(
    video: VideoItem, countdownSeconds: Int
  ) -> TimeInterval {
    TimeInterval(max(0, countdownSeconds)) + video.effectivePlaybackDuration + 30
  }

  private func finish(_ error: Error?) {
    guard isPresenting || completion != nil else { return }
    for player in players {
      player.pause()
      player.replaceCurrentItem(with: nil)
    }
    players.removeAll()
    for window in windows {
      window.orderOut(nil)
      window.close()
    }
    windows.removeAll()
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
    endObserver = nil
    failureObserver = nil
    stallObserver = nil
    itemStatusObservation = nil
    playbackStatusObservation = nil
    playbackStartTask?.cancel()
    playbackStartTask = nil
    stallWatchdogTask?.cancel()
    stallWatchdogTask = nil
    presentationWatchdogTask?.cancel()
    presentationWatchdogTask = nil
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = nil
    if cursorHidden {
      NSCursor.unhide()
      cursorHidden = false
    }
    previousApplication?.activate()
    previousApplication = nil
    presentationID = nil
    let pending = completion
    completion = nil
    if let error {
      logger.error(
        "Scare ended with error: \(error.localizedDescription, privacy: .private(mask: .hash))")
      pending?.resume(throwing: error)
    } else {
      pending?.resume()
    }
  }

  private func screenUnderPointer(fallback: NSScreen) -> NSScreen {
    let point = NSEvent.mouseLocation
    return NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main ?? fallback
  }
}

extension NSColor {
  fileprivate convenience init?(hex: String) {
    let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard clean.count == 6, let value = Int(clean, radix: 16) else { return nil }
    self.init(
      red: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
      blue: CGFloat(value & 0xff) / 255, alpha: 1)
  }
}
