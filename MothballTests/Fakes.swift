import Foundation

@testable import Mothball

/// One log shared by the fake phone and vault, so tests can assert the order of operations across
/// both.
actor CallLog {
  private(set) var calls: [String] = []

  func append(_ call: String) {
    calls.append(call)
  }
}

struct FakeError: Error {}

func summary(_ id: String, phone: String? = nil, email: String? = nil) -> ContactSummary {
  ContactSummary(
    id: id, givenName: id.capitalized, familyName: "", organizationName: "",
    phoneNumbers: phone.map { [$0] } ?? [], emailAddresses: email.map { [$0] } ?? [])
}

actor FakePhone: PhoneContactStore {
  enum Failure: Hashable {
    case archive
    case delete
    case restore
  }

  private(set) var contacts: [ContactSummary]
  private let log: CallLog
  private let failing: Set<Failure>

  init(contacts: [ContactSummary], log: CallLog, failing: Set<Failure> = []) {
    self.contacts = contacts
    self.log = log
    self.failing = failing
  }

  func access() -> ContactAccess { .full }
  func requestAccess() -> ContactAccess { .full }
  func scopeName() -> String { "iCloud" }
  func summaries() -> [ContactSummary] { contacts }

  func archive(_ id: String) async throws -> ContactArchive {
    await log.append("phone.archive \(id)")
    if failing.contains(.archive) {
      throw FakeError()
    }
    guard let contact = contacts.first(where: { $0.id == id }) else {
      throw PhoneContactStoreError.notFound(id)
    }
    return ContactArchive(
      summary: contact, containerIdentifier: "icloud", keyedArchive: Data(id.utf8), vCard: Data())
  }

  func delete(_ id: String) async throws {
    await log.append("phone.delete \(id)")
    if failing.contains(.delete) {
      throw FakeError()
    }
    contacts.removeAll { $0.id == id }
  }

  func restore(_ archive: ContactArchive) async throws -> RestoreOutcome {
    await log.append("phone.restore \(archive.summary.id)")
    if failing.contains(.restore) {
      throw FakeError()
    }
    contacts.append(archive.summary)
    return RestoreOutcome(identifier: archive.summary.id, differences: [])
  }
}

actor FakeVault: VaultStore {
  enum Failure: Hashable {
    case save
    case markRestored
    case discard
  }

  nonisolated let location = VaultLocation.iCloud
  private(set) var mothballed: [VaultEntry] = []
  private(set) var restored: [VaultEntry] = []
  private var archives: [String: ContactArchive] = [:]
  private let log: CallLog
  private let failing: Set<Failure>

  init(log: CallLog, failing: Set<Failure> = []) {
    self.log = log
    self.failing = failing
  }

  /// Puts an archive straight into Mothballed without logging, for restore tests.
  func seed(_ contact: ContactSummary) -> VaultEntry {
    let entry = makeEntry(contact)
    mothballed.append(entry)
    archives[entry.id] = ContactArchive(
      summary: contact, containerIdentifier: "icloud", keyedArchive: Data(contact.id.utf8),
      vCard: Data())
    return entry
  }

  func entries() -> VaultListing {
    VaultListing(entries: mothballed, unreadable: [])
  }

  func save(_ archive: ContactArchive, note: String, to shelf: VaultShelf) async throws
    -> VaultEntry
  {
    await log.append("vault.save \(archive.summary.id) \(shelf)")
    if failing.contains(.save) {
      throw FakeError()
    }
    var entry = makeEntry(archive.summary)
    entry.note = note
    archives[entry.id] = archive
    switch shelf {
    case .mothballed: mothballed.append(entry)
    case .restored: restored.append(entry)
    }
    return entry
  }

  func archive(for entry: VaultEntry) throws -> ContactArchive {
    guard let archive = archives[entry.id] else { throw FakeError() }
    return archive
  }

  func markRestored(_ entry: VaultEntry) async throws {
    await log.append("vault.markRestored \(entry.summary.id)")
    if failing.contains(.markRestored) {
      throw FakeError()
    }
    mothballed.removeAll { $0.id == entry.id }
    restored.append(entry)
  }

  func discard(_ entry: VaultEntry) async throws {
    await log.append("vault.discard \(entry.summary.id)")
    if failing.contains(.discard) {
      throw FakeError()
    }
    mothballed.removeAll { $0.id == entry.id }
    archives[entry.id] = nil
  }

  func updateNote(_ note: String, for entry: VaultEntry) -> VaultEntry {
    var updated = entry
    updated.note = note
    if let index = mothballed.firstIndex(where: { $0.id == entry.id }) {
      mothballed[index] = updated
    }
    return updated
  }

  private func makeEntry(_ contact: ContactSummary) -> VaultEntry {
    VaultEntry(
      schemaVersion: VaultEntry.currentSchemaVersion, id: UUID().uuidString, archivedAt: Date(),
      originalIdentifier: contact.id, containerIdentifier: "icloud", summary: contact, note: "")
  }
}
