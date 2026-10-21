import Foundation
import Observability
import Testing

@testable import Mothball

@Suite("FileVault")
struct FileVaultTests {
  private let root = FileManager.default.temporaryDirectory.appending(
    path: "FileVaultTests-\(UUID().uuidString)", directoryHint: .isDirectory)

  private func makeVault() -> FileVault {
    FileVault(root: root, location: .local, observer: recordingObserver("FileVault"))
  }

  private func makeArchive(_ id: String = "alex") -> ContactArchive {
    ContactArchive(
      summary: summary(id, phone: "555-0101"), containerIdentifier: "icloud",
      keyedArchive: Data("archive-\(id)".utf8), vCard: Data("BEGIN:VCARD\nEND:VCARD\n".utf8))
  }

  private func removeRoot() {
    try? FileManager.default.removeItem(at: root)
  }

  @Test("a saved entry is listed and reads back byte for byte")
  func savesAndReads() async throws {
    defer { removeRoot() }
    let vault = makeVault()
    let archive = makeArchive()

    let entry = try await vault.save(archive, note: "moved away", to: .mothballed)

    let listing = try await vault.entries()
    #expect(listing.entries.map(\.id) == [entry.id])
    #expect(listing.entries.first?.note == "moved away")
    #expect(listing.unreadable.isEmpty)
    let readBack = try await vault.archive(for: entry)
    #expect(readBack.keyedArchive == archive.keyedArchive)
    #expect(readBack.vCard == archive.vCard)

    let directory = root.appending(path: "Mothballed/\(entry.directoryName)")
    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    #expect(files == ["contact.archive", "contact.vcf", "entry.json"])
  }

  @Test("saving to Restored doesn't list the entry as mothballed")
  func savesToRestored() async throws {
    defer { removeRoot() }
    let vault = makeVault()

    let entry = try await vault.save(makeArchive(), note: "", to: .restored)

    #expect(try await vault.entries().entries.isEmpty)
    let restored = root.appending(path: "Restored/\(entry.directoryName)")
    #expect(FileManager.default.fileExists(atPath: restored.path))
  }

  @Test("marking an entry restored moves its directory to Restored")
  func marksRestored() async throws {
    defer { removeRoot() }
    let vault = makeVault()
    let entry = try await vault.save(makeArchive(), note: "", to: .mothballed)

    try await vault.markRestored(entry)

    #expect(try await vault.entries().entries.isEmpty)
    let restored = root.appending(path: "Restored/\(entry.directoryName)/contact.archive")
    #expect(FileManager.default.fileExists(atPath: restored.path))
  }

  @Test("an updated note persists")
  func updatesNote() async throws {
    defer { removeRoot() }
    let vault = makeVault()
    let entry = try await vault.save(makeArchive(), note: "", to: .mothballed)

    let updated = try await vault.updateNote("lost touch after college", for: entry)

    #expect(updated.note == "lost touch after college")
    #expect(try await vault.entries().entries.first?.note == "lost touch after college")
  }

  @Test("discarding an entry removes it")
  func discards() async throws {
    defer { removeRoot() }
    let vault = makeVault()
    let entry = try await vault.save(makeArchive(), note: "", to: .mothballed)

    try await vault.discard(entry)

    #expect(try await vault.entries().entries.isEmpty)
    let directory = root.appending(path: "Mothballed/\(entry.directoryName)")
    #expect(!FileManager.default.fileExists(atPath: directory.path))
  }

  @Test("an entry that can't be decoded is reported, not dropped silently")
  func reportsUnreadable() async throws {
    defer { removeRoot() }
    let vault = makeVault()
    let good = try await vault.save(makeArchive(), note: "", to: .mothballed)
    let broken = root.appending(path: "Mothballed/Broken 12345678", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: broken.appending(path: "entry.json"))

    let listing = try await vault.entries()

    #expect(listing.entries.map(\.id) == [good.id])
    #expect(listing.unreadable == ["Broken 12345678"])
  }

  @Test("an empty vault lists nothing")
  func emptyVault() async throws {
    defer { removeRoot() }

    let listing = try await makeVault().entries()

    #expect(listing.entries.isEmpty)
    #expect(listing.unreadable.isEmpty)
  }

  @Test("directory names strip path separators")
  func directoryName() {
    let entry = VaultEntry(
      schemaVersion: 1, id: "ABCDEFGH-1234", archivedAt: Date(), originalIdentifier: "x",
      containerIdentifier: nil,
      summary: ContactSummary(
        id: "x", givenName: "AC/DC", familyName: "Fan: 1", organizationName: "",
        phoneNumbers: [], emailAddresses: []),
      note: "")

    #expect(entry.directoryName == "AC-DC Fan- 1 ABCDEFGH")
  }
}
