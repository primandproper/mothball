import Foundation

/// The slice of a contact the app needs for lists, matching and vault metadata. Full records only
/// exist as archives, so nothing outside the contact store handles a `CNContact`.
struct ContactSummary: Codable, Hashable, Identifiable, Sendable {
  let id: String
  let givenName: String
  let familyName: String
  let organizationName: String
  let phoneNumbers: [String]
  let emailAddresses: [String]

  var displayName: String {
    let name = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
    if !name.isEmpty {
      return name
    }
    if !organizationName.isEmpty {
      return organizationName
    }
    return phoneNumbers.first ?? emailAddresses.first ?? "No Name"
  }

  var detail: String? {
    phoneNumbers.first ?? emailAddresses.first
  }

  var sectionTitle: String {
    guard let first = displayName.first, first.isLetter else { return "#" }
    return String(first).uppercased()
  }
}
