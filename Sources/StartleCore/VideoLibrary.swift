import AppKit
import AVFoundation
import Foundation
import Observation
import os

@MainActor @Observable
public final class VideoLibrary {
    public private(set) var videos: [VideoItem] = []
    public private(set) var errorMessage: String?

    private let storageURL: URL
    private let logger = Logger(subsystem: "com.startle.app", category: "videos")
    private let supportedExtensions = Set(["mp4", "mov", "m4v"])

    public init(storageURL: URL? = nil) {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Startle", isDirectory: true)
        self.storageURL = storageURL ?? root.appendingPathComponent("VideoLibrary.json")
        load()
        refreshAvailability()
    }

    public var enabledVideos: [VideoItem] { videos.filter(\.isEnabled).filter { !$0.isMissing } }

    @discardableResult
    public func importVideos(from urls: [URL]) async -> Int {
        var imported = 0
        for url in urls {
            do {
                let item = try await makeItem(for: url)
                if !videos.contains(where: { $0.lastKnownPath == item.lastKnownPath }) {
                    videos.append(item); imported += 1
                }
            } catch {
                errorMessage = error.localizedDescription
                logger.error("Import failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        save()
        return imported
    }

    public func update(_ item: VideoItem) {
        guard let index = videos.firstIndex(where: { $0.id == item.id }) else { return }
        videos[index] = item
        save()
    }

    public func remove(_ item: VideoItem) {
        videos.removeAll { $0.id == item.id }
        save()
    }

    public func randomEnabledVideo() -> VideoItem? { enabledVideos.randomElement() }

    public func resolve(_ item: VideoItem) throws -> (url: URL, securityScoped: Bool) {
        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: item.bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            markMissing(item.id)
            throw StartleError.videoUnavailable(item.displayName)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            markMissing(item.id)
            throw StartleError.videoUnavailable(item.displayName)
        }
        let accessed = url.startAccessingSecurityScopedResource()
        if stale, let refreshed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil),
           let index = videos.firstIndex(where: { $0.id == item.id }) {
            videos[index].bookmarkData = refreshed
            videos[index].lastKnownPath = url.path
            videos[index].isMissing = false
            save()
        }
        return (url, accessed)
    }

    public func thumbnail(for item: VideoItem, size: CGSize = CGSize(width: 160, height: 90)) async -> NSImage? {
        guard let access = try? resolve(item) else { return nil }
        defer { if access.securityScoped { access.url.stopAccessingSecurityScopedResource() } }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: access.url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        let time = CMTime(seconds: min(item.trimStart + 0.25, max(0, item.duration - 0.1)), preferredTimescale: 600)
        guard let result = try? await generator.image(at: time) else { return nil }
        return NSImage(cgImage: result.image, size: size)
    }

    public func clearError() { errorMessage = nil }

    private func makeItem(for url: URL) async throws -> VideoItem {
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else { throw StartleError.unsupportedVideo(url.lastPathComponent) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isPlayable)) == true else { throw StartleError.unsupportedVideo(url.lastPathComponent) }
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        guard duration.isFinite, duration > 0 else { throw StartleError.unsupportedVideo(url.lastPathComponent) }
        let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: [.nameKey], relativeTo: nil)
        return VideoItem(displayName: url.deletingPathExtension().lastPathComponent, bookmarkData: bookmark, duration: duration, lastKnownPath: url.path)
    }

    private func markMissing(_ id: UUID) {
        guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
        videos[index].isMissing = true
        save()
    }

    private func refreshAvailability() {
        for index in videos.indices {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: videos[index].bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                videos[index].isMissing = !FileManager.default.fileExists(atPath: url.path)
                videos[index].lastKnownPath = url.path
            } else { videos[index].isMissing = true }
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL), let decoded = try? JSONDecoder().decode([VideoItem].self, from: data) else { return }
        videos = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(videos).write(to: storageURL, options: .atomic)
        } catch { logger.error("Could not save video library: \(error.localizedDescription, privacy: .public)") }
    }
}
