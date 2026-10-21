import Testing

@testable import Mothball

@Suite("ContactMatching")
struct ContactMatchingTests {
  @Test("matches the same number written differently")
  func matchesPhone() {
    let target = summary("alex", phone: "555-010-2000")
    let candidates = [summary("readded", phone: "+1 (555) 010-2000"), summary("other")]

    #expect(ContactMatching.matches(for: target, in: candidates).map(\.id) == ["readded"])
  }

  @Test("matches email case-insensitively")
  func matchesEmail() {
    let target = summary("alex", email: " Alex@Example.com")
    let candidates = [summary("readded", email: "alex@example.com")]

    #expect(ContactMatching.matches(for: target, in: candidates).map(\.id) == ["readded"])
  }

  @Test("doesn't match on short numbers")
  func ignoresShortNumbers() {
    let target = summary("alex", phone: "911")
    let candidates = [summary("emergency", phone: "911")]

    #expect(ContactMatching.matches(for: target, in: candidates).isEmpty)
  }

  @Test("a contact with no phone or email matches nothing")
  func noHandles() {
    #expect(ContactMatching.matches(for: summary("alex"), in: [summary("alex")]).isEmpty)
  }

  @Test("different numbers don't match")
  func differentNumbers() {
    let target = summary("alex", phone: "555-010-2000")
    let candidates = [summary("other", phone: "555-010-2001")]

    #expect(ContactMatching.matches(for: target, in: candidates).isEmpty)
  }
}
