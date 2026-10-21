import Contacts
import Testing

@testable import Mothball

@Suite("VCardPhoto")
struct VCardPhotoTests {
  @Test("an injected photo survives Apple's vCard parser")
  func roundTrips() throws {
    let contact = SpikeFixture.make(tag: "abc")
    let photo = try #require(contact.imageData)
    let vCard = try CNContactVCardSerialization.data(with: [contact])

    let injected = VCardPhoto.inject(photo, into: vCard)

    let parsed = try #require(try CNContactVCardSerialization.contacts(with: injected).first)
    #expect(parsed.imageData != nil)
    #expect(parsed.givenName == contact.givenName)
  }

  @Test("folded lines stay within 75 octets and unfold to the original")
  func folds() {
    let line = "PHOTO;ENCODING=b;TYPE=PNG:" + String(repeating: "A", count: 400)

    let folded = VCardPhoto.fold(line, newline: "\r\n")

    let lines = folded.components(separatedBy: "\r\n")
    #expect(lines.allSatisfy { $0.utf8.count <= 75 })
    #expect(lines.dropFirst().allSatisfy { $0.hasPrefix(" ") })
    #expect(folded.replacing("\r\n ", with: "") == line)
  }

  @Test("a vCard that already has a photo is left alone")
  func keepsExistingPhoto() {
    let vCard = Data("BEGIN:VCARD\nVERSION:3.0\nPHOTO;ENCODING=b:AAAA\nEND:VCARD\n".utf8)

    #expect(VCardPhoto.inject(Data([0x89, 0x50, 0x4E, 0x47]), into: vCard) == vCard)
  }
}
