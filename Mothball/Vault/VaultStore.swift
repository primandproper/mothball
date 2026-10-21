import Foundation

/// The app's metadata for one archived contact, stored as `entry.json` beside the archive files.
struct VaultEntry: Codable, Hashable, Identifiable, Sendable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let id: String
  let archivedAt: Date
  /// The contact's identifier on the phone when it was archived.
  let originalIdentifier: String
  let containerIdentifier: String?
  let summary: ContactSummary
  var note: String

  /// Human-readable so the vault makes sense browsed in Files; the id suffix keeps it unique.
  var directoryName: String {
    let name = summary.displayName
      .replacing("/", with: "-")
      .replacing(":", with: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
    return "\(name.isEmpty ? "Contact" : name) \(id.prefix(8))"
  }
}

enum VaultLocation: String, Sendable {
  case iCloud
  /// iCloud Drive is unavailable, so the vault only exists on this phone.
  case local
}

/// Mothballed holds what's archived now; Restored keeps everything that came back (or was
/// replaced), so the vault never destroys a record.
enum VaultShelf: Sendable {
  case mothballed
  case restored
}

struct VaultListing: Sendable {
  let entries: [VaultEntry]
  /// Directory names whose entry couldn't be read.
  let unreadable: [String]
}

protocol VaultStore: Sendable {
  var location: VaultLocation { get }
  func entries() async throws -> VaultListing
  /// Writes and verifies every file before the entry becomes visible to `entries()`.
  func save(_ archive: ContactArchive, note: String, to shelf: VaultShelf) async throws
    -> VaultEntry
  func archive(for entry: VaultEntry) async throws -> ContactArchive
  func markRestored(_ entry: VaultEntry) async throws
  /// Removes an entry outright. Only for rolling back an archive whose contact is still on the
  /// phone.
  func discard(_ entry: VaultEntry) async throws
  func updateNote(_ note: String, for entry: VaultEntry) async throws -> VaultEntry
}

enum VaultError: LocalizedError {
  case verificationFailed(String)

  var errorDescription: String? {
    switch self {
    case .verificationFailed(let file):
      "\(file) didn't read back the way it was written."
    }
  }
}
