import Contacts
import Testing

@testable import Mothball

@Suite("ContactDiff")
struct ContactDiffTests {
  @Test("identical contacts have no differences")
  func identical() throws {
    let before = SpikeFixture.make(tag: "abc")
    let after = try #require(before.copy() as? CNContact)

    #expect(ContactDiff.compare(before, after).isEmpty)
  }

  @Test("a changed field is reported with its before and after values")
  func changedField() throws {
    let before = SpikeFixture.make(tag: "abc")
    let after = try #require(before.mutableCopy() as? CNMutableContact)
    after.jobTitle = "Retired"

    #expect(
      ContactDiff.compare(before, after) == [
        .init(field: "jobTitle", before: "Fixture", after: "Retired")
      ])
  }

  @Test("a dropped photo is reported")
  func droppedPhoto() throws {
    let before = SpikeFixture.make(tag: "abc")
    let after = try #require(before.mutableCopy() as? CNMutableContact)
    after.imageData = nil

    let diff = try #require(ContactDiff.compare(before, after).first { $0.field == "imageData" })
    #expect(diff.after == "none")
  }

  @Test("a relabeled phone number is reported")
  func relabeledPhoneNumber() throws {
    let before = SpikeFixture.make(tag: "abc")
    let after = try #require(before.mutableCopy() as? CNMutableContact)
    after.phoneNumbers = after.phoneNumbers.map {
      $0.settingLabel($0.label == "burner" ? CNLabelOther : $0.label)
    }

    #expect(ContactDiff.compare(before, after).map(\.field) == ["phoneNumbers"])
  }
}
