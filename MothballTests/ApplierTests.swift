import Observability
import Testing

@testable import Mothball

@Suite("Applier")
struct ApplierTests {
  private func makeApplier(_ phone: FakePhone, _ vault: FakeVault) -> Applier {
    Applier(phone: phone, vault: vault, observer: recordingObserver("Applier"))
  }

  private func isFailure(_ outcome: ApplyResult.Outcome) -> Bool {
    if case .failed = outcome {
      return true
    }
    return false
  }

  // MARK: - Archiving

  @Test("archives to the vault before deleting from the phone")
  func archives() async {
    let log = CallLog()
    let alex = summary("alex", phone: "555-0101")
    let phone = FakePhone(contacts: [alex], log: log)
    let vault = FakeVault(log: log)

    let results = await makeApplier(phone, vault).apply(
      ChangePlan(archive: [alex], restore: []), resolutions: [:])

    #expect(results.map(\.outcome) == [.archived])
    #expect(
      await log.calls == ["phone.archive alex", "vault.save alex mothballed", "phone.delete alex"])
    #expect(await phone.contacts.isEmpty)
    #expect(await vault.mothballed.map(\.summary.id) == ["alex"])
  }

  @Test("skips a contact that left the phone after it was marked")
  func skipsMissingContact() async {
    let log = CallLog()
    let phone = FakePhone(contacts: [], log: log)
    let vault = FakeVault(log: log)

    let results = await makeApplier(phone, vault).apply(
      ChangePlan(archive: [summary("alex")], restore: []), resolutions: [:])

    #expect(results.map(\.outcome) == [.skipped("No longer on your phone.")])
    #expect(await log.calls.isEmpty)
  }

  @Test("leaves the phone alone when the vault save fails")
  func vaultSaveFails() async throws {
    let log = CallLog()
    let alex = summary("alex")
    let phone = FakePhone(contacts: [alex], log: log)
    let vault = FakeVault(log: log, failing: [.save])

    let results = await makeApplier(phone, vault).apply(
      ChangePlan(archive: [alex], restore: []), resolutions: [:])

    #expect(isFailure(try #require(results.first).outcome))
    #expect(await log.calls == ["phone.archive alex", "vault.save alex mothballed"])
    #expect(await phone.contacts == [alex])
  }

  @Test("discards the vault copy when the phone delete fails")
  func phoneDeleteFails() async throws {
    let log = CallLog()
    let alex = summary("alex")
    let phone = FakePhone(contacts: [alex], log: log, failing: [.delete])
    let vault = FakeVault(log: log)

    let results = await makeApplier(phone, vault).apply(
      ChangePlan(archive: [alex], restore: []), resolutions: [:])

    #expect(isFailure(try #require(results.first).outcome))
    #expect(
      await log.calls == [
        "phone.archive alex", "vault.save alex mothballed", "phone.delete alex",
        "vault.discard alex",
      ])
    #expect(await phone.contacts == [alex])
    #expect(await vault.mothballed.isEmpty)
  }

  // MARK: - Restoring

  @Test("restores and then moves the entry to Restored")
  func restores() async {
    let log = CallLog()
    let alex = summary("alex", phone: "555-0101")
    let phone = FakePhone(contacts: [], log: log)
    let vault = FakeVault(log: log)
    let entry = await vault.seed(alex)

    let results = await makeApplier(phone, vault).apply(
      ChangePlan(archive: [], restore: [entry]), resolutions: [:])

    #expect(results.map(\.outcome) == [.restored(differences: [])])
    #expect(await log.calls == ["phone.restore alex", "vault.markRestored alex"])
    #expect(await phone.contacts == [alex])
    #expect(await vault.mothballed.isEmpty)
    #expect(await vault.restored.map(\.id) == [entry.id])
  }

  @Test("keeps the entry mothballed when the restore fails")
  func restoreFails() async throws {
    let log = CallLog()
    let phone = FakePhone(contacts: [], log: log, failing: [.restore])
    let vault = FakeVault(log: log)
    let entry = await vault.seed(summary("alex"))

    let results = await makeApplier(phone, vault).apply(
      ChangePlan(archive: [], restore: [entry]), resolutions: [:])

    #expect(isFailure(try #require(results.first).outcome))
    #expect(await log.calls == ["phone.restore alex"])
    #expect(await vault.mothballed.map(\.id) == [entry.id])
  }

  // MARK: - Conflicts

  @Test("preflight reports a restore that matches a phone contact")
  func preflightFindsConflict() async throws {
    let log = CallLog()
    let onPhone = summary("readded", phone: "+1 (555) 010-1000")
    let phone = FakePhone(contacts: [onPhone], log: log)
    let vault = FakeVault(log: log)
    let entry = await vault.seed(summary("alex", phone: "555-010-1000"))

    let preflight = try await makeApplier(phone, vault).preflight(
      ChangePlan(archive: [], restore: [entry]))

    #expect(preflight.restore.isEmpty)
    let conflict = try #require(preflight.conflicts.first)
    #expect(conflict.entry.id == entry.id)
    #expect(conflict.matches == [onPhone])
  }

  @Test("keeping the phone's version only moves the entry to Restored")
  func keepPhone() async {
    let log = CallLog()
    let onPhone = summary("readded", email: "alex@example.com")
    let phone = FakePhone(contacts: [onPhone], log: log)
    let vault = FakeVault(log: log)
    let entry = await vault.seed(summary("alex", email: "Alex@Example.com"))

    let results = await makeApplier(phone, vault).apply(
      ChangePlan(archive: [], restore: [entry]), resolutions: [entry.id: .keepPhone])

    #expect(results.map(\.outcome) == [.keptPhoneVersion])
    #expect(await log.calls == ["vault.markRestored alex"])
    #expect(await phone.contacts == [onPhone])
  }

  @Test("keeping both restores alongside the match")
  func keepBoth() async {
    let log = CallLog()
    let onPhone = summary("readded", email: "alex@example.com")
    let alex = summary("alex", email: "alex@example.com")
    let phone = FakePhone(contacts: [onPhone], log: log)
    let vault = FakeVault(log: log)
    let entry = await vault.seed(alex)

    let results = await makeApplier(phone, vault).apply(
      ChangePlan(archive: [], restore: [entry]), resolutions: [entry.id: .keepBoth])

    #expect(results.map(\.outcome) == [.restored(differences: [])])
    #expect(await phone.contacts == [onPhone, alex])
  }

  @Test("replacing backs up the match, restores, then deletes the match")
  func replace() async {
    let log = CallLog()
    let onPhone = summary("readded", email: "alex@example.com")
    let alex = summary("alex", email: "alex@example.com")
    let phone = FakePhone(contacts: [onPhone], log: log)
    let vault = FakeVault(log: log)
    let entry = await vault.seed(alex)

    let results = await makeApplier(phone, vault).apply(
      ChangePlan(archive: [], restore: [entry]), resolutions: [entry.id: .replace])

    #expect(results.map(\.outcome) == [.replaced(differences: [])])
    #expect(
      await log.calls == [
        "phone.archive readded", "vault.save readded restored", "phone.restore alex",
        "vault.markRestored alex", "phone.delete readded",
      ])
    #expect(await phone.contacts == [alex])
    #expect(await vault.restored.map(\.summary.id) == ["readded", "alex"])
  }

  @Test("replacing changes nothing when the backup fails")
  func replaceBackupFails() async throws {
    let log = CallLog()
    let onPhone = summary("readded", email: "alex@example.com")
    let phone = FakePhone(contacts: [onPhone], log: log)
    let vault = FakeVault(log: log, failing: [.save])
    let entry = await vault.seed(summary("alex", email: "alex@example.com"))

    let results = await makeApplier(phone, vault).apply(
      ChangePlan(archive: [], restore: [entry]), resolutions: [entry.id: .replace])

    #expect(isFailure(try #require(results.first).outcome))
    #expect(await log.calls == ["phone.archive readded", "vault.save readded restored"])
    #expect(await phone.contacts == [onPhone])
    #expect(await vault.mothballed.map(\.id) == [entry.id])
  }

  @Test("a conflict without a resolution is skipped")
  func unresolvedConflict() async {
    let log = CallLog()
    let phone = FakePhone(contacts: [summary("readded", phone: "555-0101")], log: log)
    let vault = FakeVault(log: log)
    let entry = await vault.seed(summary("alex", phone: "555-0101"))

    let results = await makeApplier(phone, vault).apply(
      ChangePlan(archive: [], restore: [entry]), resolutions: [:])

    #expect(
      results.map(\.outcome) == [.skipped("Now matches a contact on your phone. Review it again.")])
    #expect(await log.calls.isEmpty)
  }
}
