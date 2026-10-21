import Foundation

/// What the user marked: contacts to mothball and vault entries to restore.
struct ChangePlan: Sendable {
  var archive: [ContactSummary]
  var restore: [VaultEntry]

  var isEmpty: Bool { archive.isEmpty && restore.isEmpty }
}

/// The plan checked against the phone as it is right now.
struct Preflight: Sendable {
  var archive: [ContactSummary] = []
  /// Marked for mothballing but gone from the phone since.
  var missing: [ContactSummary] = []
  var restore: [VaultEntry] = []
  var conflicts: [RestoreConflict] = []
}

struct RestoreConflict: Identifiable, Sendable {
  var id: String { entry.id }
  let entry: VaultEntry
  /// Phone contacts sharing a phone number or email address with the entry.
  let matches: [ContactSummary]
}

enum ConflictResolution: String, CaseIterable, Identifiable, Sendable {
  /// Leave the phone alone and move the vault copy to Restored.
  case keepPhone
  /// Back up the phone's version to Restored, restore the vault copy, then delete the phone's.
  case replace
  /// Restore the vault copy alongside the phone's.
  case keepBoth

  static let `default` = ConflictResolution.keepPhone

  var id: String { rawValue }

  var title: String {
    switch self {
    case .keepPhone: "Keep the phone's version"
    case .replace: "Replace with the mothballed copy"
    case .keepBoth: "Keep both"
    }
  }
}

struct ApplyResult: Identifiable, Sendable {
  enum Outcome: Equatable, Sendable {
    case archived
    case restored(differences: [String])
    case keptPhoneVersion
    case replaced(differences: [String])
    case skipped(String)
    case failed(String)
  }

  let id: String
  let name: String
  let outcome: Outcome
}
