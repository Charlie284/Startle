import AVFoundation
import AppKit
import Foundation
import Observation
import os

@MainActor @Observable
public final class VideoLibrary {
  public private(set) var videos: [VideoItem] = []
  public private(set) var errorMessage: String?
  @ObservationIgnored public var onEnabledVideosChanged: (@MainActor (Bool) -> Void)?

  private let storageURL: URL
  private let recoveryURL: URL
  private let logger = Logger(subsystem: "com.startle.app", category: "videos")
  private let supportedExtensions = Set(["mp4", "mov", "m4v"])

  public init(storageURL: URL? = nil) {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first!
      .appendingPathComponent("Startle", isDirectory: true)
    self.storageURL = storageURL ?? root.appendingPathComponent("VideoLibrary.json")
    recoveryURL = self.storageURL.deletingLastPathComponent().appendingPathComponent(
      "VideoLibrary.recovery.json")
    if load() {
      refreshAvailability()
    }
  }

  public var enabledVideos: [VideoItem] { videos.filter(\.isEnabled).filter { !$0.isMissing } }

  @discardableResult
  public func importVideos(from urls: [URL]) async -> Int {
    var imported = 0
    for url in urls {
      do {
        let item = try await makeItem(for: url)
        if !videos.contains(where: { $0.lastKnownPath == item.lastKnownPath }) {
          videos.append(item)
          imported += 1
        }
      } catch {
        errorMessage = error.localizedDescription
        logger.error("Import failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
      }
    }
    if imported > 0 {
      save()
      notifyEnabledVideosChanged()
    }
    return imported
  }

  public func update(_ item: VideoItem) {
    guard let index = videos.firstIndex(where: { $0.id == item.id }) else { return }
    var normalized = item
    normalized.normalizePlaybackSettings()
    guard videos[index] != normalized else { return }
    videos[index] = normalized
    save()
    notifyEnabledVideosChanged()
  }

  public func remove(_ item: VideoItem) {
    guard let index = videos.firstIndex(where: { $0.id == item.id }) else { return }
    videos.remove(at: index)
    save()
    notifyEnabledVideosChanged()
  }

  public func setAllEnabled(_ enabled: Bool) {
    let original = videos
    for index in videos.indices {
      videos[index].isEnabled = enabled && !videos[index].isMissing
    }
    guard videos != original else { return }
    save()
    notifyEnabledVideosChanged()
  }

  @discardableResult
  public func removeMissingVideos() -> Int {
    let originalCount = videos.count
    videos.removeAll { $0.isMissing }
    guard videos.count != originalCount else { return 0 }
    save()
    notifyEnabledVideosChanged()
    return originalCount - videos.count
  }

  @discardableResult
  public func relink(_ item: VideoItem, to url: URL) async -> Bool {
    do {
      let replacement = try await makeItem(for: url)
      applyRelink(item, with: replacement)
      save()
      notifyEnabledVideosChanged()
      return true
    } catch {
      errorMessage = error.localizedDescription
      logger.error("Relink failed: \(error.localizedDescription, privacy: .private(mask: .hash))")
      return false
    }
  }

  public func randomEnabledVideo() -> VideoItem? { enabledVideos.randomElement() }

  public func resolve(_ item: VideoItem) throws -> (url: URL, securityScoped: Bool) {
    var stale = false
    let url: URL
    do {
      url = try URL(
        resolvingBookmarkData: item.bookmarkData, options: [.withSecurityScope], relativeTo: nil,
        bookmarkDataIsStale: &stale)
    } catch {
      markMissing(item.id)
      throw StartleError.videoUnavailable(item.displayName)
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
      markMissing(item.id)
      throw StartleError.videoUnavailable(item.displayName)
    }
    let accessed = url.startAccessingSecurityScopedResource()
    if stale,
      let refreshed = try? url.bookmarkData(
        options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil),
      let index = videos.firstIndex(where: { $0.id == item.id })
    {
      videos[index].bookmarkData = refreshed
      videos[index].lastKnownPath = url.path
      videos[index].isMissing = false
      save()
    }
    return (url, accessed)
  }

  public func thumbnail(for item: VideoItem, size: CGSize = CGSize(width: 160, height: 90)) async
    -> NSImage?
  {
    guard !item.isMissing else { return nil }
    guard let access = try? resolve(item) else { return nil }
    defer { if access.securityScoped { access.url.stopAccessingSecurityScopedResource() } }
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: access.url))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = size
    let time = CMTime(
      seconds: min(item.effectiveTrimStart + 0.25, max(0, item.duration - 0.1)),
      preferredTimescale: 600)
    guard let result = try? await generator.image(at: time) else { return nil }
    return NSImage(cgImage: result.image, size: size)
  }

  public func clearError() { errorMessage = nil }

  func applyRelink(_ item: VideoItem, with replacement: VideoItem) {
    guard let index = videos.firstIndex(where: { $0.id == item.id }) else { return }
    var updated = item
    updated.displayName = replacement.displayName
    updated.bookmarkData = replacement.bookmarkData
    updated.duration = replacement.duration
    updated.lastKnownPath = replacement.lastKnownPath
    updated.isMissing = false
    updated.trimStart = min(item.trimStart, max(0, replacement.duration - 0.1))
    if let trimEnd = item.trimEnd {
      let clampedEnd = min(max(trimEnd, updated.trimStart), replacement.duration)
      updated.trimEnd = clampedEnd >= replacement.duration ? nil : clampedEnd
    }
    updated.normalizePlaybackSettings()
    videos[index] = updated
  }

  private func makeItem(for url: URL) async throws -> VideoItem {
    guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
      throw StartleError.unsupportedVideo(url.lastPathComponent)
    }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let asset = AVURLAsset(url: url)
    guard (try? await asset.load(.isPlayable)) == true else {
      throw StartleError.unsupportedVideo(url.lastPathComponent)
    }
    let duration = (try? await asset.load(.duration).seconds) ?? 0
    guard duration.isFinite, duration > 0 else {
      throw StartleError.unsupportedVideo(url.lastPathComponent)
    }
    let bookmark = try url.bookmarkData(
      options: [.withSecurityScope], includingResourceValuesForKeys: [.nameKey], relativeTo: nil)
    return VideoItem(
      displayName: url.deletingPathExtension().lastPathComponent, bookmarkData: bookmark,
      duration: duration, lastKnownPath: url.path)
  }

  private func markMissing(_ id: UUID) {
    guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
    guard !videos[index].isMissing else { return }
    videos[index].isMissing = true
    save()
    notifyEnabledVideosChanged()
  }

  private func refreshAvailability() {
    var changed = false
    for index in videos.indices {
      let original = videos[index]
      var stale = false
      if let url = try? URL(
        resolvingBookmarkData: videos[index].bookmarkData, options: [.withSecurityScope],
        relativeTo: nil, bookmarkDataIsStale: &stale)
      {
        let accessed = url.startAccessingSecurityScopedResource()
        videos[index].isMissing = !FileManager.default.fileExists(atPath: url.path)
        videos[index].lastKnownPath = url.path
        if stale,
          let refreshed = try? url.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        {
          videos[index].bookmarkData = refreshed
        }
        if accessed { url.stopAccessingSecurityScopedResource() }
      } else {
        videos[index].isMissing = true
      }
      videos[index].normalizePlaybackSettings()
      changed = changed || videos[index] != original
    }
    if changed { save() }
  }

  private func load() -> Bool {
    guard FileManager.default.fileExists(atPath: storageURL.path) else { return true }
    do {
      let data = try Data(contentsOf: storageURL)
      do {
        videos = try JSONDecoder().decode([VideoItem].self, from: data)
        for index in videos.indices {
          videos[index].normalizePlaybackSettings()
        }
        return true
      } catch {
        preserveRecoveryCopy(data)
        reportLoadFailure(error)
        return false
      }
    } catch {
      reportLoadFailure(error)
      return false
    }
  }

  private func preserveRecoveryCopy(_ data: Data) {
    do {
      try FileManager.default.createDirectory(
        at: recoveryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: recoveryURL, options: .atomic)
    } catch {
      logger.error(
        "Could not preserve video library recovery data: \(error.localizedDescription, privacy: .private(mask: .hash))"
      )
    }
  }

  private func reportLoadFailure(_ error: Error) {
    errorMessage =
      "The saved video library could not be read. The original file was left untouched and a recovery copy was preserved when possible."
    logger.error(
      "Could not load video library: \(error.localizedDescription, privacy: .private(mask: .hash))"
    )
  }

  private func notifyEnabledVideosChanged() {
    onEnabledVideosChanged?(!enabledVideos.isEmpty)
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(
        at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(videos).write(to: storageURL, options: .atomic)
    } catch {
      errorMessage =
        "The video library could not be saved. Your latest changes may not survive a restart."
      logger.error(
        "Could not save video library: \(error.localizedDescription, privacy: .private(mask: .hash))"
      )
    }
  }
}
