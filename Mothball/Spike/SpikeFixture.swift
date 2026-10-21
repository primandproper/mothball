import Contacts
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The contact the spike creates, archives, deletes and restores. Every field it fills is one the
/// archive has to carry, so the round-trip diff covers as much of the record as possible.
enum SpikeFixture {
  /// Stamped into organizationName so cleanup can only ever match contacts the spike created.
  static let marker = "Mothball Spike Fixture"
  static let givenName = "Mothball Spike"

  static let noteTestGivenName = "Mothball"
  static let noteTestFamilyName = "NoteTest"

  static func make(tag: String) -> CNMutableContact {
    let contact = CNMutableContact()
    contact.namePrefix = "Dr."
    contact.givenName = givenName
    contact.middleName = "Q"
    contact.familyName = tag
    contact.previousFamilyName = "Formerly"
    contact.nameSuffix = "Jr."
    contact.nickname = "Spikey"
    contact.phoneticGivenName = "MOTH-ball"
    contact.organizationName = marker
    contact.departmentName = "Research"
    contact.jobTitle = "Fixture"
    contact.birthday = DateComponents(year: 1990, month: 4, day: 12)
    contact.dates = [
      CNLabeledValue(
        label: CNLabelDateAnniversary,
        value: DateComponents(year: 2015, month: 6, day: 20) as NSDateComponents),
      CNLabeledValue(
        label: "met at a wedding",
        value: DateComponents(month: 9, day: 3) as NSDateComponents),
    ]
    contact.phoneNumbers = [
      CNLabeledValue(
        label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "555-0101")),
      CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: "+1 (555) 010-2000")),
      CNLabeledValue(label: "burner", value: CNPhoneNumber(stringValue: "555-0199")),
    ]
    contact.emailAddresses = [
      CNLabeledValue(label: CNLabelHome, value: "spike@example.com" as NSString),
      CNLabeledValue(label: CNLabelWork, value: "spike@work.example.com" as NSString),
    ]
    let address = CNMutablePostalAddress()
    address.street = "1 Fixture Way\nApt 2"
    address.city = "Springfield"
    address.state = "OR"
    address.postalCode = "97477"
    address.country = "United States"
    address.isoCountryCode = "us"
    contact.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: address)]
    contact.urlAddresses = [
      CNLabeledValue(label: CNLabelURLAddressHomePage, value: "https://example.com" as NSString)
    ]
    contact.contactRelations = [
      CNLabeledValue(
        label: CNLabelContactRelationFriend, value: CNContactRelation(name: "Jane Fixture"))
    ]
    contact.socialProfiles = [
      CNLabeledValue(
        label: nil,
        value: CNSocialProfile(
          urlString: nil, username: "mothballspike", userIdentifier: nil,
          service: CNSocialProfileServiceTwitter))
    ]
    contact.instantMessageAddresses = [
      CNLabeledValue(
        label: nil,
        value: CNInstantMessageAddress(username: "mothball", service: CNInstantMessageServiceSkype))
    ]
    contact.imageData = makeImage()
    return contact
  }

  /// A 128x128 PNG, drawn with CoreGraphics so it can be produced off the main actor.
  private static func makeImage() -> Data? {
    let size = 128
    guard
      let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.setFillColor(red: 0.42, green: 0.36, blue: 0.58, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(red: 0.95, green: 0.93, blue: 0.88, alpha: 1)
    context.fillEllipse(in: CGRect(x: 32, y: 32, width: 64, height: 64))
    guard let image = context.makeImage() else { return nil }

    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
  }
}
