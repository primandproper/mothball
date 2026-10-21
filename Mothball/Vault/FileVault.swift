import Foundation
import Observability

/// A vault of plain files: one directory per contact holding `contact.archive`, `contact.vcf` and
/// `entry.json`, under `Mothballed/` or `Restored/`. Every file access goes through
/// `NSFileCoordinator` so it cooperates with iCloud Drive sync.
actor FileVault: VaultStore {
  private static let archiveFile = "contact.archive"
  private static let vCardFile = "contact.vcf"
  private static let entryFile = "entry.json"

  nonisolated let location: VaultLocation
  private let root: URL
  private let logger: any Logger
  private let fileManager = FileManager.default

  init(root: URL, location: VaultLocation, observer: any Observer) {
    self.root = root
    self.location = location
    self.logger = observer.logger
  }

  /// The app's iCloud Drive folder when iCloud is available, otherwise local Documents. Resolving
  /// the ubiquity container can block, which is why this is async and nonisolated.
  static func resolve(observer: any Observer) async throws -> FileVault {
    let fm = FileManager.default
    if let container = fm.url(forUbiquityContainerIdentifier: nil) {
      let root = container.appending(path: "Documents", directoryHint: .isDirectory)
      return FileVault(root: root, location: .iCloud, observer: observer)
    }
    let documents = try fm.url(
      for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    return FileVault(root: documents, location: .local, observer: observer)
  }

  func entries() throws -> VaultListing {
    let shelf = directory(for: .mothballed)
    guard fileManager.fileExists(atPath: shelf.path) else {
      return VaultListing(entries: [], unreadable: [])
    }

    var entries: [VaultEntry] = []
    var unreadable: [String] = []
    let directories = try fileManager.contentsOfDirectory(
      at: shelf, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
    for directory in directories where directory.hasDirectoryPath {
      let file = directory.appending(path: Self.entryFile)
      do {
        if location == .iCloud {
          try fileManager.startDownloadingUbiquitousItem(at: file)
        }
        entries.append(try decoder.decode(VaultEntry.self, from: read(file)))
      } catch {
        logger.error("reading vault entry \(directory.lastPathComponent)", error)
        unreadable.append(directory.lastPathComponent)
      }
    }
    return VaultListing(entries: entries, unreadable: unreadable)
  }

  func save(_ archive: ContactArchive, note: String, to shelf: VaultShelf) throws -> VaultEntry {
    let entry = VaultEntry(
      schemaVersion: VaultEntry.currentSchemaVersion,
      id: UUID().uuidString,
      archivedAt: Date(),
      originalIdentifier: archive.summary.id,
      containerIdentifier: archive.containerIdentifier,
      summary: archive.summary,
      note: note)

    let shelfDirectory = directory(for: shelf)
    try fileManager.createDirectory(at: shelfDirectory, withIntermediateDirectories: true)
    // Files are written into a hidden staging directory and moved into place last, so a crash
    // mid-save never leaves a half-written entry that `entries()` would list.
    let staging = shelfDirectory.appending(
      path: ".\(entry.id).partial", directoryHint: .isDirectory)
    do {
      try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
      let files = [
        (Self.archiveFile, archive.keyedArchive),
        (Self.vCardFile, archive.vCard),
        (Self.entryFile, try encoder.encode(entry)),
      ]
      for (name, data) in files {
        let url = staging.appending(path: name)
        try write(data, to: url)
        guard try read(url) == data else { throw VaultError.verificationFailed(name) }
      }
      try Self.move(staging, to: shelfDirectory.appending(path: entry.directoryName))
    } catch {
      removeStaging(staging)
      throw error
    }
    return entry
  }

  func archive(for entry: VaultEntry) throws -> ContactArchive {
    let directory = entryDirectory(entry, on: .mothballed)
    return ContactArchive(
      summary: entry.summary,
      containerIdentifier: entry.containerIdentifier,
      keyedArchive: try read(directory.appending(path: Self.archiveFile)),
      vCard: try read(directory.appending(path: Self.vCardFile)))
  }

  func markRestored(_ entry: VaultEntry) throws {
    let destination = directory(for: .restored)
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    try Self.move(
      entryDirectory(entry, on: .mothballed), to: destination.appending(path: entry.directoryName))
  }

  func discard(_ entry: VaultEntry) throws {
    let url = entryDirectory(entry, on: .mothballed)
    var coordinationError: NSError?
    var removeError: Error?
    NSFileCoordinator().coordinate(
      writingItemAt: url, options: .forDeleting, error: &coordinationError
    ) {
      target in
      do {
        try fileManager.removeItem(at: target)
      } catch {
        removeError = error
      }
    }
    if let error = coordinationError ?? removeError {
      throw error
    }
  }

  func updateNote(_ note: String, for entry: VaultEntry) throws -> VaultEntry {
    var updated = entry
    updated.note = note
    try write(
      encoder.encode(updated),
      to: entryDirectory(entry, on: .mothballed).appending(path: Self.entryFile))
    return updated
  }

  // MARK: - Files

  private func directory(for shelf: VaultShelf) -> URL {
    switch shelf {
    case .mothballed: root.appending(path: "Mothballed", directoryHint: .isDirectory)
    case .restored: root.appending(path: "Restored", directoryHint: .isDirectory)
    }
  }

  private func entryDirectory(_ entry: VaultEntry, on shelf: VaultShelf) -> URL {
    directory(for: shelf).appending(path: entry.directoryName, directoryHint: .isDirectory)
  }

  private func write(_ data: Data, to url: URL) throws {
    var coordinationError: NSError?
    var writeError: Error?
    NSFileCoordinator().coordinate(
      writingItemAt: url, options: .forReplacing, error: &coordinationError
    ) { target in
      do {
        try data.write(to: target, options: .atomic)
      } catch {
        writeError = error
      }
    }
    if let error = coordinationError ?? writeError {
      throw error
    }
  }

  private func read(_ url: URL) throws -> Data {
    var coordinationError: NSError?
    var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) {
      target in
      result = Result { try Data(contentsOf: target) }
    }
    if let coordinationError {
      throw coordinationError
    }
    return try result.get()
  }

  /// Nonisolated because the accessor has to call back into the coordinator, which strict
  /// concurrency rejects when the coordinator belongs to the actor's region.
  private nonisolated static func move(_ source: URL, to destination: URL) throws {
    var coordinationError: NSError?
    var moveError: Error?
    let coordinator = NSFileCoordinator()
    coordinator.coordinate(
      writingItemAt: source, options: .forMoving, writingItemAt: destination,
      options: .forReplacing, error: &coordinationError
    ) { from, to in
      do {
        try FileManager.default.moveItem(at: from, to: to)
        coordinator.item(at: from, didMoveTo: to)
      } catch {
        moveError = error
      }
    }
    if let error = coordinationError ?? moveError {
      throw error
    }
  }

  private func removeStaging(_ staging: URL) {
    guard fileManager.fileExists(atPath: staging.path) else { return }
    do {
      try fileManager.removeItem(at: staging)
    } catch {
      logger.error("removing staging directory \(staging.lastPathComponent)", error)
    }
  }

  private var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  private var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
