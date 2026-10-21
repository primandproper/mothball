import Foundation

/// Where the spike writes archived contacts: the app's iCloud Drive folder when iCloud is
/// available, otherwise the app's local Documents directory.
struct SpikeVault: Sendable {
  enum Location: String, Sendable {
    case iCloud
    case local
  }

  let location: Location
  let directory: URL

  /// Must not run on the main thread: resolving the ubiquity container can block.
  static func resolve() throws -> SpikeVault {
    let fm = FileManager.default
    let vault: SpikeVault
    if let container = fm.url(forUbiquityContainerIdentifier: nil) {
      vault = SpikeVault(
        location: .iCloud,
        directory: container.appending(path: "Documents/spike", directoryHint: .isDirectory))
    } else {
      let documents = try fm.url(
        for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      vault = SpikeVault(
        location: .local,
        directory: documents.appending(path: "spike", directoryHint: .isDirectory))
    }
    try fm.createDirectory(at: vault.directory, withIntermediateDirectories: true)
    return vault
  }

  func write(_ data: Data, named name: String) throws -> URL {
    let url = directory.appending(path: name)
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
    return url
  }

  func read(_ url: URL) throws -> Data {
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
}
