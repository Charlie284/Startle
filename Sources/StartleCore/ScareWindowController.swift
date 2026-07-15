import AppKit
import AVFoundation
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
            countdownLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); playerLayer.frame = bounds }
}

@MainActor
public final class ScareWindowController {
    private var windows: [ScarePanel] = []
    private var players: [AVPlayer] = []
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var completion: CheckedContinuation<Void, Error>?
    private var previousApplication: NSRunningApplication?
    private var cursorHidden = false
    private let logger = Logger(subsystem: "com.startle.app", category: "playback")

    public init() {}

    public var isPresenting: Bool { !windows.isEmpty }

    public func present(video: VideoItem, url: URL, safety: SafetySettings, appearance: AppearanceSettings) async throws {
        guard !isPresenting else { return }
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else { throw StartleError.playbackFailed("The selected movie is not playable.") }
        previousApplication = NSWorkspace.shared.frontmostApplication
        makeWindows(asset: asset, video: video, safety: safety, appearance: appearance)

        try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            Task { @MainActor [weak self] in
                guard let self else { return }
                if safety.countdownSeconds > 0 {
                    for value in stride(from: safety.countdownSeconds, through: 1, by: -1) {
                        guard self.isPresenting else { return }
                        self.windows.compactMap { $0.contentView as? PlayerSurface }.forEach { $0.countdownLabel.stringValue = "\(value)" }
                        if !safety.quietMode { NSSound.beep() }
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
                guard self.isPresenting else { return }
                self.windows.compactMap { $0.contentView as? PlayerSurface }.forEach { $0.countdownLabel.stringValue = "" }
                self.players.forEach { $0.play() }
            }
        }
    }

    public func dismiss() { finish(nil) }

    private func makeWindows(asset: AVURLAsset, video: VideoItem, safety: SafetySettings, appearance: AppearanceSettings) {
        let targetScreens: [NSScreen]
        switch appearance.displayMode {
        case .allDisplays: targetScreens = NSScreen.screens
        case .fullScreen: targetScreens = [NSScreen.main ?? NSScreen.screens[0]]
        case .centered, .currentDisplay: targetScreens = [screenUnderPointer()]
        }

        for screen in targetScreens {
            let frame: NSRect
            if appearance.displayMode == .centered {
                let size = NSSize(width: min(960, screen.visibleFrame.width * 0.76), height: min(600, screen.visibleFrame.height * 0.76))
                frame = NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2, width: size.width, height: size.height)
            } else { frame = screen.frame }

            let panel = ScarePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: screen)
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = true
            panel.backgroundColor = NSColor(hex: appearance.backgroundHex) ?? .black
            panel.hidesOnDeactivate = false
            panel.escapeHandler = { [weak self] in self?.dismiss() }

            let surface = PlayerSurface(frame: frame)
            surface.layer?.backgroundColor = panel.backgroundColor.cgColor
            let item = AVPlayerItem(asset: asset)
            if let end = video.trimEnd, end > video.trimStart { item.forwardPlaybackEndTime = CMTime(seconds: min(end, video.duration), preferredTimescale: 600) }
            let player = AVPlayer(playerItem: item)
            player.volume = safety.quietMode ? 0 : Float(video.volume)
            surface.playerLayer.player = player
            surface.playerLayer.videoGravity = appearance.cropToFill ? .resizeAspectFill : .resizeAspect
            panel.contentView = surface
            panel.orderFrontRegardless()
            if video.trimStart > 0 { player.seek(to: CMTime(seconds: video.trimStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
            windows.append(panel); players.append(player)
        }

        if let firstItem = players.first?.currentItem {
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: firstItem, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.finish(nil) }
            }
            failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: firstItem, queue: .main) { [weak self] note in
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                Task { @MainActor in self?.finish(StartleError.playbackFailed(error?.localizedDescription ?? "Unknown player error")) }
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.dismiss() }; return nil }
            return event
        }
        NSApp.activate()
        windows.first?.makeKey()
        if appearance.hideCursor { NSCursor.hide(); cursorHidden = true }
    }

    private func finish(_ error: Error?) {
        guard isPresenting || completion != nil else { return }
        players.forEach { $0.pause(); $0.replaceCurrentItem(with: nil) }
        players.removeAll()
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows.removeAll()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil; failureObserver = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        previousApplication?.activate()
        previousApplication = nil
        let pending = completion; completion = nil
        if let error { logger.error("Scare ended with error: \(error.localizedDescription, privacy: .public)"); pending?.resume(throwing: error) }
        else { pending?.resume() }
    }

    private func screenUnderPointer() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6, let value = Int(clean, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255, blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }
}
