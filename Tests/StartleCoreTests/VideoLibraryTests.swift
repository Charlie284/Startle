import Foundation
import XCTest

@testable import StartleCore

@MainActor
final class VideoLibraryTests: XCTestCase {
  func testCorruptLibraryIsReportedWithoutOverwritingSourceFile() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("StartleCoreTests-\(UUID().uuidString)", isDirectory: true)
    let storageURL = directory.appendingPathComponent("VideoLibrary.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let invalidData = Data("not-json".utf8)
    try invalidData.write(to: storageURL)

    let library = VideoLibrary(storageURL: storageURL)

    XCTAssertTrue(library.videos.isEmpty)
    XCTAssertNotNil(library.errorMessage)
    XCTAssertEqual(try Data(contentsOf: storageURL), invalidData)
    XCTAssertEqual(
      try Data(contentsOf: directory.appendingPathComponent("VideoLibrary.recovery.json")),
      invalidData)
  }

  func testFailedImportDoesNotOverwriteCorruptLibrary() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storageURL = directory.appendingPathComponent("VideoLibrary.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let invalidData = Data("not-json".utf8)
    try invalidData.write(to: storageURL)
    let unsupportedURL = directory.appendingPathComponent("not-a-video.txt")
    try Data("plain text".utf8).write(to: unsupportedURL)
    let library = VideoLibrary(storageURL: storageURL)

    let imported = await library.importVideos(from: [unsupportedURL])

    XCTAssertEqual(imported, 0)
    XCTAssertEqual(try Data(contentsOf: storageURL), invalidData)
    XCTAssertEqual(
      try Data(contentsOf: directory.appendingPathComponent("VideoLibrary.recovery.json")),
      invalidData)
  }

  func testMissingLibraryStartsEmptyWithoutError() {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("StartleCoreTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let library = VideoLibrary(storageURL: directory.appendingPathComponent("VideoLibrary.json"))

    XCTAssertTrue(library.videos.isEmpty)
    XCTAssertNil(library.errorMessage)
  }

  func testRelinkPreservesPlaybackSettingsAndClampsTrimToReplacement() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storageURL = directory.appendingPathComponent("VideoLibrary.json")
    let original = VideoItem(
      displayName: "Moved Video", bookmarkData: Data("missing".utf8), duration: 10,
      isEnabled: true, volume: 0.35, trimStart: 8, trimEnd: 9,
      lastKnownPath: "/missing/Moved Video.mov", isMissing: true)
    try write([original], to: storageURL)
    let library = VideoLibrary(storageURL: storageURL)
    let loaded = try XCTUnwrap(library.videos.first)
    let replacement = VideoItem(
      displayName: "Found Video", bookmarkData: Data("replacement".utf8), duration: 5,
      lastKnownPath: "/found/Found Video.mov")

    library.applyRelink(loaded, with: replacement)

    let relinked = try XCTUnwrap(library.videos.first)
    XCTAssertEqual(relinked.id, original.id)
    XCTAssertEqual(relinked.displayName, "Found Video")
    XCTAssertEqual(relinked.bookmarkData, replacement.bookmarkData)
    XCTAssertEqual(relinked.lastKnownPath, replacement.lastKnownPath)
    XCTAssertEqual(relinked.duration, 5)
    XCTAssertTrue(relinked.isEnabled)
    XCTAssertEqual(relinked.volume, 0.35)
    XCTAssertEqual(relinked.trimStart, 4.9, accuracy: 0.001)
    XCTAssertNil(relinked.trimEnd)
    XCTAssertFalse(relinked.isMissing)
  }

  func testBulkEnableSkipsMissingVideosAndBulkRemovalKeepsAvailableVideos() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storageURL = directory.appendingPathComponent("VideoLibrary.json")
    let first = VideoItem(
      displayName: "Available", bookmarkData: Data("first".utf8), duration: 3,
      isEnabled: false, lastKnownPath: "/missing/Available.mov", isMissing: true)
    let second = VideoItem(
      displayName: "Missing", bookmarkData: Data("second".utf8), duration: 3,
      isEnabled: true, lastKnownPath: "/missing/Missing.mov", isMissing: true)
    try write([first, second], to: storageURL)
    let library = VideoLibrary(storageURL: storageURL)
    let loadedFirst = try XCTUnwrap(library.videos.first { $0.id == first.id })
    let replacement = VideoItem(
      displayName: "Available", bookmarkData: Data("replacement".utf8), duration: 3,
      isEnabled: false, lastKnownPath: "/found/Available.mov")
    library.applyRelink(loadedFirst, with: replacement)

    library.setAllEnabled(true)

    XCTAssertTrue(try XCTUnwrap(library.videos.first { $0.id == first.id }).isEnabled)
    XCTAssertFalse(try XCTUnwrap(library.videos.first { $0.id == second.id }).isEnabled)
    XCTAssertEqual(library.removeMissingVideos(), 1)
    XCTAssertEqual(library.videos.map(\.id), [first.id])
  }

  func testPlaybackSettingsAreNormalizedAtModelBoundary() throws {
    let item = VideoItem(
      displayName: "Trimmed", bookmarkData: Data(), duration: 10, volume: 2,
      trimStart: -5, trimEnd: -1, lastKnownPath: "/tmp/Trimmed.mov")

    XCTAssertEqual(item.volume, 1)
    XCTAssertEqual(item.trimStart, 0)
    XCTAssertEqual(try XCTUnwrap(item.trimEnd), 0.01, accuracy: 0.0001)
    XCTAssertEqual(item.effectivePlaybackDuration, 0.01, accuracy: 0.0001)
  }

  func testTrimStartCannotReachOrExceedDuration() {
    let item = VideoItem(
      displayName: "Short", bookmarkData: Data(), duration: 5, volume: -1,
      trimStart: 100, trimEnd: 100, lastKnownPath: "/tmp/Short.mov")

    XCTAssertEqual(item.volume, 0)
    XCTAssertEqual(item.trimStart, 4.99, accuracy: 0.0001)
    XCTAssertNil(item.trimEnd)
    XCTAssertEqual(item.effectivePlaybackDuration, 0.01, accuracy: 0.0001)
  }

  func testCoordinatorDisablesSchedulingWhenNoVideoRemains() async throws {
    let suiteName = "StartleCoreTests.ScareCoordinator.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = SettingsStore(defaults: defaults)
    settings.values.onboardingCompleted = true
    try settings.setEnabled(true, hasVideos: true, emergencyShortcutAvailable: true)
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = VideoLibrary(storageURL: directory.appendingPathComponent("VideoLibrary.json"))
    let presenter = FakeScarePresenter()
    let coordinator = ScareCoordinator(
      settings: settings, library: library, windowController: presenter)

    await coordinator.trigger()

    XCTAssertFalse(settings.values.scaresEnabled)
    XCTAssertEqual(settings.errorMessage, StartleError.noVideos.localizedDescription)
    XCTAssertEqual(presenter.presentationCount, 0)
  }

  func testCoordinatorRecordsOnlyCompletedPresentations() async throws {
    let suiteName = "StartleCoreTests.ScareCoordinator.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = SettingsStore(defaults: defaults)
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let movieURL = directory.appendingPathComponent("clip.mov")
    try Data("placeholder".utf8).write(to: movieURL)
    let bookmark = try movieURL.bookmarkData(
      options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    let item = VideoItem(
      displayName: "Clip", bookmarkData: bookmark, duration: 2,
      lastKnownPath: movieURL.path)
    let storageURL = directory.appendingPathComponent("VideoLibrary.json")
    try write([item], to: storageURL)
    let library = VideoLibrary(storageURL: storageURL)
    let presenter = FakeScarePresenter()
    presenter.wasPresented = false
    let coordinator = ScareCoordinator(
      settings: settings, library: library, windowController: presenter)

    await coordinator.trigger()

    XCTAssertEqual(presenter.presentationCount, 1)
    XCTAssertEqual(settings.values.totalScareCount, 0)

    presenter.wasPresented = true
    await coordinator.trigger()

    XCTAssertEqual(presenter.presentationCount, 2)
    XCTAssertEqual(settings.values.totalScareCount, 1)
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("StartleCoreTests-\(UUID().uuidString)", isDirectory: true)
  }

  private func write(_ items: [VideoItem], to storageURL: URL) throws {
    try FileManager.default.createDirectory(
      at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(items).write(to: storageURL)
  }
}

@MainActor
private final class FakeScarePresenter: ScarePresenting {
  var wasPresented = true
  private(set) var presentationCount = 0
  private(set) var dismissCount = 0

  func present(
    video: VideoItem, url: URL, safety: SafetySettings, appearance: AppearanceSettings
  ) async throws -> Bool {
    presentationCount += 1
    return wasPresented
  }

  func dismiss() {
    dismissCount += 1
  }
}
