import Contacts
import Foundation
import Observability

/// Measures the archive, delete and restore round trip against the real contact store. It only
/// ever writes to contacts it created itself (stamped with ``SpikeFixture/marker``) and to the
/// contact named "Mothball NoteTest", which exists solely to be deleted by this run.
actor SpikeRunner {
  private let observer: any Observer
  private let store = CNContactStore()
  private var steps: [SpikeStep] = []

  init(observer: any Observer) {
    self.observer = observer
  }

  static var reportURL: URL {
    URL.documentsDirectory.appending(path: "spike-report.json")
  }

  func run() async -> SpikeReport {
    // The closure form of `operation` can't be called from an actor under Swift 6: its body isn't
    // `sending` or isolated to the caller, so the manual form stands in.
    let op = observer.begin("spike.run")
    defer { op.end() }
    steps = []
    let startedAt = Date()
    await runSteps()
    let report = SpikeReport(startedAt: startedAt, finishedAt: Date(), steps: steps)
    op.set("steps.failed", report.steps.filter { $0.outcome == .fail }.count)
    persist(report)
    return report
  }

  private func runSteps() async {
    guard await authorize() else { return }
    inventoryContainers()
    countLinkedCards()
    removeLeftoverFixtures()

    guard let original = createAndFetchFixture() else { return }
    let archive = writeToVault(serialize(original))
    var fromVCard: CNContact?
    if let data = archive.vcard {
      fromVCard = parseVCard(data, original: original)
    }
    var fromKeyedArchive: CNContact?
    if let data = archive.keyed {
      fromKeyedArchive = unarchive(data, original: original)
    }

    guard delete(original) else { return }
    if let fromVCard {
      restore(fromVCard, source: "vCard", original: original)
    }
    if let fromKeyedArchive {
      restore(fromKeyedArchive, source: "keyed archive", original: original)
    }

    noteContactTests()
  }

  // MARK: - Steps

  private func authorize() async -> Bool {
    let name = "authorization"
    var status = CNContactStore.authorizationStatus(for: .contacts)
    if status == .notDetermined {
      do {
        _ = try await store.requestAccess(for: .contacts)
      } catch {
        record(name, .fail, ["requesting access", error.spikeDescription])
        return false
      }
      status = CNContactStore.authorizationStatus(for: .contacts)
    }

    switch status {
    case .authorized:
      record(name, .pass, ["full access"])
      return true
    case .limited:
      record(name, .info, ["limited access: only contacts picked in the system sheet are visible"])
      return true
    case .denied, .restricted, .notDetermined:
      record(name, .fail, ["status \(status.rawValue); grant access in Settings and rerun"])
      return false
    @unknown default:
      record(name, .fail, ["unknown status \(status.rawValue)"])
      return false
    }
  }

  private func inventoryContainers() {
    let name = "containers"
    do {
      let defaultID = store.defaultContainerIdentifier()
      let details = try store.containers(matching: nil).map { container in
        let predicate = CNContact.predicateForContactsInContainer(
          withIdentifier: container.identifier)
        let count = try store.unifiedContacts(
          matching: predicate, keysToFetch: [CNContactGivenNameKey as CNKeyDescriptor]
        ).count
        let label = container.name.isEmpty ? "<unnamed>" : container.name
        let suffix = container.identifier == defaultID ? " (default)" : ""
        return "\(label): type=\(describe(container.type)) contacts=\(count)\(suffix)"
      }
      record(name, .info, details)
    } catch {
      record(name, .fail, [error.spikeDescription])
    }
  }

  private func countLinkedCards() {
    let name = "linked cards"
    do {
      let unified = try countContacts(unified: true)
      let separate = try countContacts(unified: false)
      record(
        name, .info,
        [
          "unified=\(unified) separate=\(separate)",
          "\(separate - unified) cards are linked into another card",
        ])
    } catch {
      record(name, .fail, [error.spikeDescription])
    }
  }

  private func removeLeftoverFixtures() {
    let name = "leftover cleanup"
    do {
      let leftovers = try store.unifiedContacts(
        matching: CNContact.predicateForContacts(matchingName: SpikeFixture.givenName),
        keysToFetch: [
          CNContactGivenNameKey as CNKeyDescriptor,
          CNContactOrganizationNameKey as CNKeyDescriptor,
        ]
      ).filter {
        $0.givenName == SpikeFixture.givenName && $0.organizationName == SpikeFixture.marker
      }
      guard !leftovers.isEmpty else {
        record(name, .pass, ["none found"])
        return
      }
      let request = CNSaveRequest()
      for leftover in leftovers {
        request.delete(mutable(leftover))
      }
      try store.execute(request)
      record(name, .pass, ["deleted \(leftovers.count) fixture contacts left by an earlier run"])
    } catch {
      record(name, .fail, [error.spikeDescription])
    }
  }

  private func createAndFetchFixture() -> CNContact? {
    let tag = String(UUID().uuidString.prefix(8))
    let fixture = SpikeFixture.make(tag: tag)
    do {
      let request = CNSaveRequest()
      request.add(fixture, toContainerWithIdentifier: nil)
      try store.execute(request)
      record("create fixture", .pass, ["identifier=\(fixture.identifier)", "tag=\(tag)"])
    } catch {
      record("create fixture", .fail, [error.spikeDescription])
      return nil
    }

    let vCardKeys =
      [CNContactVCardSerialization.descriptorForRequiredKeys()] + ContactDiff.archiveKeys
    do {
      let contact = try store.unifiedContact(
        withIdentifier: fixture.identifier, keysToFetch: vCardKeys)
      record(
        "fetch with vCard keys", .pass,
        [
          "descriptorForRequiredKeys() fetched without the notes entitlement",
          "note key available: \(contact.isKeyAvailable(CNContactNoteKey))",
        ])
      return contact
    } catch {
      record(
        "fetch with vCard keys", .fail, [error.spikeDescription, "falling back to explicit keys"])
    }

    do {
      let contact = try store.unifiedContact(
        withIdentifier: fixture.identifier, keysToFetch: ContactDiff.archiveKeys)
      record("fetch with explicit keys", .pass)
      return contact
    } catch {
      record("fetch with explicit keys", .fail, [error.spikeDescription])
      return nil
    }
  }

  private func serialize(_ contact: CNContact) -> (vcard: Data?, keyed: Data?) {
    var vcard: Data?
    do {
      let data = try CNContactVCardSerialization.data(with: [contact])
      let text = String(decoding: data, as: UTF8.self)
      record(
        "vCard serialize", .pass,
        [
          "\(data.count) bytes",
          "has PHOTO: \(text.contains("PHOTO"))",
          "has NOTE: \(text.contains("NOTE"))",
        ])
      vcard = data
    } catch {
      record("vCard serialize", .fail, [error.spikeDescription])
    }

    var keyed: Data?
    do {
      let data = try NSKeyedArchiver.archivedData(
        withRootObject: contact, requiringSecureCoding: true)
      record("keyed archive serialize", .pass, ["\(data.count) bytes"])
      keyed = data
    } catch {
      record("keyed archive serialize", .fail, [error.spikeDescription])
    }
    return (vcard, keyed)
  }

  /// Returns what was read back from disk rather than what was written, so later steps parse the
  /// bytes the vault actually holds.
  private func writeToVault(_ archive: (vcard: Data?, keyed: Data?)) -> (
    vcard: Data?, keyed: Data?
  ) {
    let name = "vault write and read back"
    do {
      let vault = try SpikeVault.resolve()
      var details = ["location=\(vault.location.rawValue)", "directory=\(vault.directory.path)"]
      func roundTrip(_ data: Data?, _ filename: String) throws -> Data? {
        guard let data else { return nil }
        let back = try vault.read(vault.write(data, named: filename))
        details.append("\(filename): \(data.count) bytes, identical after read: \(back == data)")
        return back
      }
      let result = (
        vcard: try roundTrip(archive.vcard, "fixture.vcf"),
        keyed: try roundTrip(archive.keyed, "fixture.contact")
      )
      record(name, vault.location == .iCloud ? .pass : .info, details)
      return result
    } catch {
      record(name, .fail, [error.spikeDescription])
      return archive
    }
  }

  private func parseVCard(_ data: Data, original: CNContact) -> CNContact? {
    let name = "vCard parse"
    do {
      guard let parsed = try CNContactVCardSerialization.contacts(with: data).first else {
        record(name, .fail, ["no contact in vCard data"])
        return nil
      }
      recordDiff(name, original, parsed)
      return parsed
    } catch {
      record(name, .fail, [error.spikeDescription])
      return nil
    }
  }

  private func unarchive(_ data: Data, original: CNContact) -> CNContact? {
    let name = "keyed archive decode"
    do {
      guard
        let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: CNContact.self, from: data)
      else {
        record(name, .fail, ["archive decoded to nil"])
        return nil
      }
      recordDiff(name, original, decoded)
      return decoded
    } catch {
      record(name, .fail, [error.spikeDescription])
      return nil
    }
  }

  private func delete(_ contact: CNContact) -> Bool {
    let name = "delete fixture"
    do {
      let request = CNSaveRequest()
      request.delete(mutable(contact))
      try store.execute(request)
    } catch {
      record(name, .fail, [error.spikeDescription])
      return false
    }
    let gone =
      (try? store.unifiedContact(
        withIdentifier: contact.identifier,
        keysToFetch: [CNContactGivenNameKey as CNKeyDescriptor])) == nil
    record(name, gone ? .pass : .fail, ["gone from the store: \(gone)"])
    return gone
  }

  private func restore(_ archived: CNContact, source: String, original: CNContact) {
    let name = "restore from \(source)"
    let copy = mutable(archived)
    do {
      let request = CNSaveRequest()
      request.add(copy, toContainerWithIdentifier: nil)
      try store.execute(request)
    } catch {
      record(name, .fail, ["adding", error.spikeDescription])
      return
    }

    do {
      let restored = try store.unifiedContact(
        withIdentifier: copy.identifier, keysToFetch: ContactDiff.archiveKeys)
      let diffs = ContactDiff.compare(original, restored)
      record(
        name, diffs.isEmpty ? .pass : .lossy,
        [
          "kept original identifier: \(restored.identifier == original.identifier)"
        ] + diffs.map(describe))

      let cleanup = CNSaveRequest()
      cleanup.delete(mutable(restored))
      try store.execute(cleanup)
    } catch {
      record(name, .fail, ["fetching or cleaning up", error.spikeDescription])
    }
  }

  /// Reproduces the DTS-confirmed macOS behavior (FB23452026) on iOS: does saving a contact that
  /// carries a note fail without the notes entitlement, for update and for delete?
  private func noteContactTests() {
    let contact: CNContact
    do {
      let matches = try store.unifiedContacts(
        matching: CNContact.predicateForContacts(
          matchingName: "\(SpikeFixture.noteTestGivenName) \(SpikeFixture.noteTestFamilyName)"),
        keysToFetch: ContactDiff.archiveKeys
      ).filter {
        $0.givenName == SpikeFixture.noteTestGivenName
          && $0.familyName == SpikeFixture.noteTestFamilyName
      }
      guard let match = matches.first else {
        record(
          "note contact", .skip,
          [
            "no contact named Mothball NoteTest",
            "create one with a note in Contacts, then rerun; this run will delete it",
          ])
        return
      }
      contact = match
    } catch {
      record("note contact", .fail, [error.spikeDescription])
      return
    }

    do {
      let update = mutable(contact)
      update.jobTitle = "mothball update test"
      let request = CNSaveRequest()
      request.update(update)
      try store.execute(request)
      record("note contact update", .pass, ["update succeeded without the entitlement"])

      let revert = mutable(contact)
      let revertRequest = CNSaveRequest()
      revertRequest.update(revert)
      try store.execute(revertRequest)
    } catch {
      record("note contact update", .fail, [error.spikeDescription])
    }

    do {
      let request = CNSaveRequest()
      request.delete(mutable(contact))
      try store.execute(request)
      record("note contact delete", .pass, ["delete succeeded without the entitlement"])
    } catch {
      record("note contact delete", .fail, [error.spikeDescription])
    }
  }

  // MARK: - Helpers

  private func record(_ name: String, _ outcome: SpikeStep.Outcome, _ details: [String] = []) {
    steps.append(SpikeStep(name: name, outcome: outcome, details: details))
    observer.logger
      .withValue("step", name)
      .withValue("outcome", outcome.rawValue)
      .info(details.joined(separator: "; "))
  }

  private func recordDiff(_ name: String, _ before: CNContact, _ after: CNContact) {
    let diffs = ContactDiff.compare(before, after)
    record(name, diffs.isEmpty ? .pass : .lossy, diffs.map(describe))
  }

  private func persist(_ report: SpikeReport) {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      try encoder.encode(report).write(to: Self.reportURL, options: .atomic)
    } catch {
      observer.logger.error("writing spike report", error)
    }
  }

  private func countContacts(unified: Bool) throws -> Int {
    let request = CNContactFetchRequest(keysToFetch: [CNContactGivenNameKey as CNKeyDescriptor])
    request.unifyResults = unified
    var count = 0
    try store.enumerateContacts(with: request) { _, _ in count += 1 }
    return count
  }

  private func describe(_ diff: ContactDiff.Difference) -> String {
    "\(diff.field): \(diff.before) -> \(diff.after)"
  }

  private func describe(_ type: CNContainerType) -> String {
    switch type {
    case .local: "local"
    case .exchange: "exchange"
    case .cardDAV: "cardDAV"
    case .unassigned: "unassigned"
    @unknown default: "unknown(\(type.rawValue))"
    }
  }

  /// `mutableCopy()` on a `CNContact` always yields a `CNMutableContact`; the fallback exists only
  /// to avoid a force cast.
  private func mutable(_ contact: CNContact) -> CNMutableContact {
    contact.mutableCopy() as? CNMutableContact ?? CNMutableContact()
  }
}
