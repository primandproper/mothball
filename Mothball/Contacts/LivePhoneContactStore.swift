import Contacts
import Foundation
import Observability

/// `PhoneContactStore` backed by the system contact store. Every read is scoped to the default
/// container (the account new contacts go to, normally iCloud), and fetches don't unify, so each
/// summary is one card in that account rather than a merged view across accounts.
actor LivePhoneContactStore: PhoneContactStore {
  private let store = CNContactStore()
  private let logger: any Logger

  init(observer: any Observer) {
    self.logger = observer.logger
  }

  func access() -> ContactAccess {
    switch CNContactStore.authorizationStatus(for: .contacts) {
    case .notDetermined: .notDetermined
    case .limited: .limited
    case .authorized: .full
    case .denied, .restricted: .denied
    @unknown default: .denied
    }
  }

  func requestAccess() async throws -> ContactAccess {
    _ = try await store.requestAccess(for: .contacts)
    return access()
  }

  func scopeName() throws -> String {
    let id = store.defaultContainerIdentifier()
    let container = try store.containers(
      matching: CNContainer.predicateForContainers(withIdentifiers: [id])
    ).first
    guard let name = container?.name, !name.isEmpty else { return "On My iPhone" }
    return name
  }

  func summaries() throws -> [ContactSummary] {
    let request = CNContactFetchRequest(keysToFetch: ContactSummary.keys)
    request.predicate = CNContact.predicateForContactsInContainer(
      withIdentifier: store.defaultContainerIdentifier())
    request.unifyResults = false
    var summaries: [ContactSummary] = []
    try store.enumerateContacts(with: request) { contact, _ in
      summaries.append(ContactSummary(contact))
    }
    return summaries
  }

  func archive(_ id: String) throws -> ContactArchive {
    let contact = try fetch(
      id, keys: [CNContactVCardSerialization.descriptorForRequiredKeys()] + ContactDiff.archiveKeys)

    let keyed = try NSKeyedArchiver.archivedData(
      withRootObject: contact, requiringSecureCoding: true)
    guard let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: CNContact.self, from: keyed)
    else { throw PhoneContactStoreError.undecodableArchive }
    let differences = ContactDiff.compare(contact, decoded)
    guard differences.isEmpty else {
      throw PhoneContactStoreError.archiveMismatch(differences.map(\.description))
    }

    var vCard = try CNContactVCardSerialization.data(with: [contact])
    if let photo = contact.imageData {
      vCard = VCardPhoto.inject(photo, into: vCard)
    }

    let container = try store.containers(
      matching: CNContainer.predicateForContainerOfContact(withIdentifier: id)
    ).first
    return ContactArchive(
      summary: ContactSummary(contact), containerIdentifier: container?.identifier,
      keyedArchive: keyed, vCard: vCard)
  }

  func delete(_ id: String) throws {
    let contact = try fetch(id, keys: [CNContactIdentifierKey as CNKeyDescriptor])
    let request = CNSaveRequest()
    request.delete(mutable(contact))
    try store.execute(request)
  }

  func restore(_ archive: ContactArchive) throws -> RestoreOutcome {
    guard
      let archived = try NSKeyedUnarchiver.unarchivedObject(
        ofClass: CNContact.self, from: archive.keyedArchive)
    else { throw PhoneContactStoreError.undecodableArchive }

    // A keyed archive restores under its original identifier. When that identifier is still on
    // the phone ("keep both"), restore from the vCard instead so the two records can't collide.
    let source: CNContact
    if exists(archived.identifier) {
      guard let parsed = try CNContactVCardSerialization.contacts(with: archive.vCard).first else {
        throw PhoneContactStoreError.undecodableArchive
      }
      source = parsed
    } else {
      source = archived
    }

    let copy = mutable(source)
    let request = CNSaveRequest()
    request.add(copy, toContainerWithIdentifier: existingContainer(archive.containerIdentifier))
    try store.execute(request)

    let restored = try fetch(copy.identifier, keys: ContactDiff.archiveKeys)
    let differences = ContactDiff.compare(archived, restored).map(\.description)
    if !differences.isEmpty {
      logger.info("restored \(restored.identifier) with differences: \(differences)")
    }
    return RestoreOutcome(identifier: restored.identifier, differences: differences)
  }

  private func fetch(_ id: String, keys: [CNKeyDescriptor]) throws -> CNContact {
    let request = CNContactFetchRequest(keysToFetch: keys)
    request.predicate = CNContact.predicateForContacts(withIdentifiers: [id])
    request.unifyResults = false
    var found: CNContact?
    try store.enumerateContacts(with: request) { contact, stop in
      found = contact
      stop.pointee = true
    }
    guard let found else { throw PhoneContactStoreError.notFound(id) }
    return found
  }

  private func exists(_ id: String) -> Bool {
    (try? fetch(id, keys: [CNContactIdentifierKey as CNKeyDescriptor])) != nil
  }

  /// Falls back to the default container (`nil`) when the original account is gone.
  private func existingContainer(_ id: String?) -> String? {
    guard let id else { return nil }
    do {
      let matches = try store.containers(
        matching: CNContainer.predicateForContainers(withIdentifiers: [id]))
      return matches.isEmpty ? nil : id
    } catch {
      logger.error("looking up container \(id)", error)
      return nil
    }
  }

  /// `mutableCopy()` on a `CNContact` always yields a `CNMutableContact`; the fallback exists only
  /// to avoid a force cast.
  private func mutable(_ contact: CNContact) -> CNMutableContact {
    contact.mutableCopy() as? CNMutableContact ?? CNMutableContact()
  }
}

extension ContactSummary {
  static var keys: [CNKeyDescriptor] {
    [
      CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
      CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
    ].map { $0 as CNKeyDescriptor }
  }

  init(_ contact: CNContact) {
    self.init(
      id: contact.identifier,
      givenName: contact.givenName,
      familyName: contact.familyName,
      organizationName: contact.organizationName,
      phoneNumbers: contact.phoneNumbers.map(\.value.stringValue),
      emailAddresses: contact.emailAddresses.map { $0.value as String })
  }
}
