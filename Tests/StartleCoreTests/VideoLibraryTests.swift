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

  func testLegacyLibraryLoadsSelectionDefaultsAndMigratesOnSave() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let item = try availableItem(named: "Legacy", in: directory)
    let encoded = try JSONEncoder().encode([item])
    var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
    payload[0].removeValue(forKey: "selectionWeight")
    payload[0].removeValue(forKey: "isRare")
    payload[0].removeValue(forKey: "selectionCooldown")
    payload[0].removeValue(forKey: "lastPlayedAt")
    let storageURL = directory.appendingPathComponent("VideoLibrary.json")
    try JSONSerialization.data(withJSONObject: payload).write(to: storageURL)
    let library = VideoLibrary(storageURL: storageURL)

    let loaded = try XCTUnwrap(library.videos.first)
    XCTAssertEqual(loaded.selectionWeight, 1)
    XCTAssertFalse(loaded.isRare)
    XCTAssertEqual(loaded.selectionCooldown, 0)
    XCTAssertNil(loaded.lastPlayedAt)
    XCTAssertEqual(library.selectionSettings, VideoSelectionSettings())

    library.updateSelectionSettings(
      VideoSelectionSettings(mode: .shuffleBag, recentHistoryCount: 5))
    let reloaded = VideoLibrary(storageURL: storageURL)

    XCTAssertEqual(reloaded.videos.map(\.id), [item.id])
    XCTAssertEqual(reloaded.selectionSettings.mode, .shuffleBag)
    XCTAssertEqual(reloaded.selectionSettings.recentHistoryCount, 5)
  }

  func testWeightedSelectionUsesPerVideoWeightAndRareMultiplier() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let light = try availableItem(named: "Light", in: directory, selectionWeight: 1)
    let heavy = try availableItem(named: "Heavy", in: directory, selectionWeight: 9)
    let storageURL = directory.appendingPathComponent("VideoLibrary.json")
    try write([light, heavy], to: storageURL)
    let selectsLight = VideoLibrary(storageURL: storageURL, randomValue: { 0.05 })
    let selectsHeavy = VideoLibrary(storageURL: storageURL, randomValue: { 0.2 })

    XCTAssertEqual(selectsLight.randomEnabledVideo()?.id, light.id)
    XCTAssertEqual(selectsHeavy.randomEnabledVideo()?.id, heavy.id)

    var rare = heavy
    rare.isRare = true
    XCTAssertEqual(rare.effectiveSelectionWeight, 0.9, accuracy: 0.0001)
  }

  func testWeightedSelectionDoesNotRepeatRecentHistory() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let items = try (0..<6).map {
      try availableItem(named: "Video \($0)", in: directory)
    }
    let storageURL = directory.appendingPathComponent("VideoLibrary.json")
    try write(items, to: storageURL)
    let library = VideoLibrary(storageURL: storageURL, randomValue: { 0 })
    library.updateSelectionSettings(
      VideoSelectionSettings(mode: .weightedRandom, recentHistoryCount: 4))
    var played: [UUID] = []

    for offset in 0..<18 {
      let selected = try XCTUnwrap(
        library.randomEnabledVideo(at: Date(timeIntervalSince1970: Double(offset))))
      XCTAssertFalse(played.suffix(4).contains(selected.id))
      played.append(selected.id)
      library.recordPlayback(
        of: selected, at: Date(timeIntervalSince1970: Double(offset)))
    }
  }

  func testVideoCooldownMakesOnlyThatVideoTemporarilyIneligible() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let now = Date(timeIntervalSince1970: 10_000)
    let coolingDown = try availableItem(
      named: "Cooling Down", in: directory, selectionCooldown: 3_600, lastPlayedAt: now)
    let available = try availableItem(named: "Available", in: directory)
    let storageURL = directory.appendingPathComponent("VideoLibrary.json")
    try write([coolingDown, available], to: storageURL)
    let library = VideoLibrary(storageURL: storageURL, randomValue: { 0 })

    XCTAssertEqual(library.randomEnabledVideo(at: now)?.id, available.id)
    XCTAssertNil(library.nextVideoEligibilityDate(at: now))
    XCTAssertEqual(
      library.randomEnabledVideo(at: now.addingTimeInterval(3_600))?.id, coolingDown.id)

    var alsoCoolingDown = available
    alsoCoolingDown.selectionCooldown = 3_600
    alsoCoolingDown.lastPlayedAt = now
    library.update(alsoCoolingDown)
    XCTAssertNil(library.randomEnabledVideo(at: now))
    XCTAssertEqual(library.nextVideoEligibilityDate(at: now), now.addingTimeInterval(3_600))
  }

  func testShuffleBagEligibilityDateUsesOnlyRemainingVideos() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let now = Date(timeIntervalSince1970: 10_000)
    let available = try availableItem(named: "Available", in: directory)
    let coolingDown = try availableItem(
      named: "Cooling Down", in: directory, selectionCooldown: 3_600, lastPlayedAt: now)
    let storageURL = directory.appendingPathComponent("VideoLibrary.json")
    try write([available, coolingDown], to: storageURL)
    let library = VideoLibrary(storageURL: storageURL, randomValue: { 0 })
    library.updateSelectionSettings(
      VideoSelectionSettings(mode: .shuffleBag, recentHistoryCount: 1))

    let selected = try XCTUnwrap(library.randomEnabledVideo(at: now))
    XCTAssertEqual(selected.id, available.id)
    library.recordPlayback(of: selected, at: now)

    XCTAssertNil(library.randomEnabledVideo(at: now))
    XCTAssertEqual(library.nextVideoEligibilityDate(at: now), now.addingTimeInterval(3_600))
  }

  func testCooldownFilteringStillAvoidsTheMostRecentlyPlayedEligibleVideo() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let items = try (0..<4).map {
      try availableItem(named: "History \($0)", in: directory)
    }
    let storageURL = directory.appendingPathComponent("VideoLibrary.json")
    try write(items, to: storageURL)
    let library = VideoLibrary(storageURL: storageURL, randomValue: { 0.99 })
    for (offset, item) in items.enumerated() {
      library.recordPlayback(
        of: item, at: Date(timeIntervalSince1970: Double(offset)))
    }
    for item in items.suffix(2) {
      var coolingDown = item
      coolingDown.selectionCooldown = 100
      coolingDown.lastPlayedAt = Date(timeIntervalSince1970: 3)
      library.update(coolingDown)
    }

    let selected = library.randomEnabledVideo(at: Date(timeIntervalSince1970: 4))

    XCTAssertEqual(selected?.id, items[0].id)
  }

  func testShuffleBagPlaysEveryEnabledVideoOncePerCycle() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let items = try (0..<5).map {
      try availableItem(named: "Bag \($0)", in: directory)
    }
    let storageURL = directory.appendingPathComponent("VideoLibrary.json")
    try write(items, to: storageURL)
    let library = VideoLibrary(storageURL: storageURL, randomValue: { 0 })
    library.updateSelectionSettings(
      VideoSelectionSettings(mode: .shuffleBag, recentHistoryCount: 3))
    var cycles: [[UUID]] = [[], []]

    for index in 0..<(items.count * 2) {
      let selected = try XCTUnwrap(
        library.randomEnabledVideo(at: Date(timeIntervalSince1970: Double(index))))
      cycles[index / items.count].append(selected.id)
      library.recordPlayback(
        of: selected, at: Date(timeIntervalSince1970: Double(index)))
    }

    XCTAssertEqual(Set(cycles[0]), Set(items.map(\.id)))
    XCTAssertEqual(Set(cycles[1]), Set(items.map(\.id)))
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
    presenter.outcome = .skipped
    let coordinator = ScareCoordinator(
      settings: settings, library: library, windowController: presenter)

    await coordinator.trigger()

    XCTAssertEqual(presenter.presentationCount, 1)
    XCTAssertEqual(settings.values.totalScareCount, 0)
    XCTAssertNil(library.videos.first?.lastPlayedAt)
    XCTAssertEqual(settings.values.activityEvents.first?.kind, .skipped)

    presenter.outcome = .completed
    await coordinator.trigger()

    XCTAssertEqual(presenter.presentationCount, 2)
    XCTAssertEqual(settings.values.totalScareCount, 1)
    XCTAssertNotNil(library.videos.first?.lastPlayedAt)
    XCTAssertEqual(settings.values.activityEvents.first?.kind, .played)
  }

  func testCoordinatorRecordsDismissedAndFailedPresentations() async throws {
    let suiteName = "StartleCoreTests.ScareCoordinator.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = SettingsStore(defaults: defaults)
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let item = try availableItem(named: "Clip", in: directory)
    let storageURL = directory.appendingPathComponent("VideoLibrary.json")
    try write([item], to: storageURL)
    let library = VideoLibrary(storageURL: storageURL)
    let presenter = FakeScarePresenter()
    let coordinator = ScareCoordinator(
      settings: settings, library: library, windowController: presenter)

    presenter.outcome = .dismissed
    await coordinator.trigger()
    XCTAssertEqual(settings.values.activityEvents.first?.kind, .dismissed)
    XCTAssertEqual(settings.values.totalScareCount, 0)

    presenter.error = StartleError.playbackFailed("Test failure")
    await coordinator.trigger()
    XCTAssertEqual(settings.values.activityEvents.first?.kind, .failed)
    XCTAssertEqual(settings.values.activityEvents.first?.reason, .playbackFailed)
    XCTAssertEqual(settings.values.totalScareCount, 0)
  }

  func testCoordinatorKeepsSchedulingEnabledWhenEveryVideoIsCoolingDown() async throws {
    let suiteName = "StartleCoreTests.ScareCoordinator.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = SettingsStore(defaults: defaults)
    settings.values.onboardingCompleted = true
    try settings.setEnabled(true, hasVideos: true, emergencyShortcutAvailable: true)
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let item = try availableItem(
      named: "Cooling Down", in: directory, selectionCooldown: 3_600,
      lastPlayedAt: Date())
    let storageURL = directory.appendingPathComponent("VideoLibrary.json")
    try write([item], to: storageURL)
    let library = VideoLibrary(storageURL: storageURL)
    let presenter = FakeScarePresenter()
    let coordinator = ScareCoordinator(
      settings: settings, library: library, windowController: presenter)

    await coordinator.trigger()

    XCTAssertTrue(settings.values.scaresEnabled)
    XCTAssertNil(settings.errorMessage)
    XCTAssertEqual(presenter.presentationCount, 0)
  }

  func testCoordinatorNeverPresentsOverAnExcludedFrontmostApplication() async throws {
    let suiteName = "StartleCoreTests.ScareCoordinator.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = SettingsStore(defaults: defaults)
    settings.values.safety.excludedApplications = [
      ExcludedApplication(bundleIdentifier: "us.zoom.xos", displayName: "zoom.us")
    ]
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = VideoLibrary(storageURL: directory.appendingPathComponent("VideoLibrary.json"))
    let presenter = FakeScarePresenter()
    let coordinator = ScareCoordinator(
      settings: settings, library: library, windowController: presenter,
      frontmostApplicationBundleIdentifier: { "us.zoom.xos" })

    await coordinator.trigger()

    XCTAssertEqual(presenter.presentationCount, 0)
    XCTAssertNil(settings.errorMessage)
    XCTAssertEqual(settings.values.totalScareCount, 0)
    XCTAssertEqual(settings.values.activityEvents.first?.kind, .skipped)
    XCTAssertEqual(settings.values.activityEvents.first?.reason, .excludedApplication)
    XCTAssertEqual(settings.values.activityEvents.first?.context, "zoom.us")
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

  private func availableItem(
    named name: String, in directory: URL, selectionWeight: Double = 1,
    selectionCooldown: TimeInterval = 0, lastPlayedAt: Date? = nil
  ) throws -> VideoItem {
    let url = directory.appendingPathComponent("\(name).mov")
    try Data("placeholder".utf8).write(to: url)
    let bookmark = try url.bookmarkData(
      options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    return VideoItem(
      displayName: name, bookmarkData: bookmark, duration: 2, lastKnownPath: url.path,
      selectionWeight: selectionWeight, selectionCooldown: selectionCooldown,
      lastPlayedAt: lastPlayedAt)
  }
}

@MainActor
private final class FakeScarePresenter: ScarePresenting {
  var outcome = ScarePresentationOutcome.completed
  var error: Error?
  private(set) var presentationCount = 0
  private(set) var dismissCount = 0

  func present(
    video: VideoItem, url: URL, safety: SafetySettings, appearance: AppearanceSettings
  ) async throws -> ScarePresentationOutcome {
    presentationCount += 1
    if let error { throw error }
    return outcome
  }

  func dismiss() {
    dismissCount += 1
  }
}
