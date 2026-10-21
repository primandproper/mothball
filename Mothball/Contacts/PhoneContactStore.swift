import Foundation

enum ContactAccess: Sendable {
  case notDetermined
  case denied
  case limited
  case full
}

/// Everything needed to put a contact back exactly as it was. The keyed archive is what restores
/// read; the vCard is the portable copy any contacts app can import.
struct ContactArchive: Sendable {
  let summary: ContactSummary
  let containerIdentifier: String?
  let keyedArchive: Data
  let vCard: Data
}

struct RestoreOutcome: Sendable {
  let identifier: String
  /// Fields that differ between the archive and what the contact store holds after the restore.
  let differences: [String]
}

/// The phone's contacts, scoped to the default account.
protocol PhoneContactStore: Sendable {
  func access() async -> ContactAccess
  func requestAccess() async throws -> ContactAccess
  func scopeName() async throws -> String
  func summaries() async throws -> [ContactSummary]
  /// Fetches the full record and verifies the archive decodes back to it field for field.
  func archive(_ id: String) async throws -> ContactArchive
  func delete(_ id: String) async throws
  func restore(_ archive: ContactArchive) async throws -> RestoreOutcome
}

enum PhoneContactStoreError: LocalizedError {
  case notFound(String)
  case undecodableArchive
  case archiveMismatch([String])

  var errorDescription: String? {
    switch self {
    case .notFound:
      "The contact is no longer on this phone."
    case .undecodableArchive:
      "The archived contact couldn't be decoded."
    case .archiveMismatch(let differences):
      "The archive didn't match the contact: \(differences.joined(separator: "; "))"
    }
  }
}
