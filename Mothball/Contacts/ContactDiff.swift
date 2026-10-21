import Contacts

/// Field-by-field comparison of two contacts, rendered as strings so a lossy round trip shows up as
/// a readable before/after pair in the spike report.
enum ContactDiff {
  struct Difference: Equatable, Sendable, CustomStringConvertible {
    let field: String
    let before: String
    let after: String

    var description: String { "\(field): \(before) -> \(after)" }
  }

  /// Every key the spike archives. The note key is deliberately absent: fetching it without the
  /// `com.apple.developer.contacts.notes` entitlement fails the whole fetch.
  static let archiveKeyNames: [String] = fields.map(\.key) + [CNContactThumbnailImageDataKey]

  static var archiveKeys: [CNKeyDescriptor] {
    archiveKeyNames.map { $0 as CNKeyDescriptor }
  }

  static func compare(_ before: CNContact, _ after: CNContact) -> [Difference] {
    fields.compactMap { field in
      let b = render(before, field)
      let a = render(after, field)
      return a == b ? nil : Difference(field: field.name, before: b, after: a)
    }
  }

  private struct Field: Sendable {
    let name: String
    let key: String
    let render: @Sendable (CNContact) -> String
  }

  private static func render(_ contact: CNContact, _ field: Field) -> String {
    contact.isKeyAvailable(field.key) ? field.render(contact) : "<not fetched>"
  }

  private static let fields: [Field] = [
    Field(name: "contactType", key: CNContactTypeKey) { "\($0.contactType.rawValue)" },
    Field(name: "namePrefix", key: CNContactNamePrefixKey) { $0.namePrefix },
    Field(name: "givenName", key: CNContactGivenNameKey) { $0.givenName },
    Field(name: "middleName", key: CNContactMiddleNameKey) { $0.middleName },
    Field(name: "familyName", key: CNContactFamilyNameKey) { $0.familyName },
    Field(name: "previousFamilyName", key: CNContactPreviousFamilyNameKey) {
      $0.previousFamilyName
    },
    Field(name: "nameSuffix", key: CNContactNameSuffixKey) { $0.nameSuffix },
    Field(name: "nickname", key: CNContactNicknameKey) { $0.nickname },
    Field(name: "phoneticGivenName", key: CNContactPhoneticGivenNameKey) { $0.phoneticGivenName },
    Field(name: "phoneticMiddleName", key: CNContactPhoneticMiddleNameKey) {
      $0.phoneticMiddleName
    },
    Field(name: "phoneticFamilyName", key: CNContactPhoneticFamilyNameKey) {
      $0.phoneticFamilyName
    },
    Field(name: "organizationName", key: CNContactOrganizationNameKey) { $0.organizationName },
    Field(name: "phoneticOrganizationName", key: CNContactPhoneticOrganizationNameKey) {
      $0.phoneticOrganizationName
    },
    Field(name: "departmentName", key: CNContactDepartmentNameKey) { $0.departmentName },
    Field(name: "jobTitle", key: CNContactJobTitleKey) { $0.jobTitle },
    Field(name: "birthday", key: CNContactBirthdayKey) { render($0.birthday) },
    Field(name: "nonGregorianBirthday", key: CNContactNonGregorianBirthdayKey) {
      render($0.nonGregorianBirthday)
    },
    Field(name: "dates", key: CNContactDatesKey) {
      labeled($0.dates) { render($0 as DateComponents) }
    },
    Field(name: "phoneNumbers", key: CNContactPhoneNumbersKey) {
      labeled($0.phoneNumbers) { $0.stringValue }
    },
    Field(name: "emailAddresses", key: CNContactEmailAddressesKey) {
      labeled($0.emailAddresses) { $0 as String }
    },
    Field(name: "postalAddresses", key: CNContactPostalAddressesKey) {
      labeled($0.postalAddresses) {
        [$0.street, $0.city, $0.state, $0.postalCode, $0.country, $0.isoCountryCode]
          .joined(separator: "|")
      }
    },
    Field(name: "urlAddresses", key: CNContactUrlAddressesKey) {
      labeled($0.urlAddresses) { $0 as String }
    },
    Field(name: "contactRelations", key: CNContactRelationsKey) {
      labeled($0.contactRelations) { $0.name }
    },
    Field(name: "socialProfiles", key: CNContactSocialProfilesKey) {
      labeled($0.socialProfiles) {
        [$0.service, $0.username, $0.urlString, $0.userIdentifier].joined(separator: "|")
      }
    },
    Field(name: "instantMessageAddresses", key: CNContactInstantMessageAddressesKey) {
      labeled($0.instantMessageAddresses) { "\($0.service)|\($0.username)" }
    },
    Field(name: "imageDataAvailable", key: CNContactImageDataAvailableKey) {
      "\($0.imageDataAvailable)"
    },
    Field(name: "imageData", key: CNContactImageDataKey) {
      $0.imageData.map { "\($0.count) bytes" } ?? "none"
    },
  ]

  private static func labeled<V>(
    _ values: [CNLabeledValue<V>], _ render: (V) -> String
  ) -> String {
    values.map { "\($0.label ?? "<nil>")=\(render($0.value))" }.joined(separator: ", ")
  }

  private static func render(_ components: DateComponents?) -> String {
    guard let components else { return "none" }
    let calendar = components.calendar.map { "\($0.identifier)" } ?? "nil"
    return [components.year, components.month, components.day]
      .map { $0.map(String.init) ?? "_" }
      .joined(separator: "-") + " (\(calendar))"
  }
}
