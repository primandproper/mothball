import Foundation
import Observation

// Selective import: Observability also exports `struct Observation` (a recording test double),
// which shadows the Observation module that the @Observable macro expands against.
import protocol Observability.Observer

@MainActor
@Observable
final class AppModel {
  enum Phase {
    case loading
    case needsAccess(ContactAccess)
    case ready
    case failed(String)
  }

  private(set) var phase: Phase = .loading
  private(set) var contacts: [ContactSummary] = []
  private(set) var vaultEntries: [VaultEntry] = []
  private(set) var unreadableEntries: [String] = []
  private(set) var scopeName = ""
  private(set) var vaultLocation: VaultLocation?
  var errorMessage: String?

  var pendingArchive: Set<ContactSummary.ID> = []
  var pendingRestore: Set<VaultEntry.ID> = []

  let diagnostics: SpikeRunner

  private let phone: any PhoneContactStore
  private let makeVault: @Sendable () async throws -> any VaultStore
  private let observer: any Observer
  private var vault: (any VaultStore)?

  init(
    phone: any PhoneContactStore,
    makeVault: @escaping @Sendable () async throws -> any VaultStore,
    observer: any Observer,
    diagnostics: SpikeRunner
  ) {
    self.phone = phone
    self.makeVault = makeVault
    self.observer = observer
    self.diagnostics = diagnostics
  }

  var pendingCount: Int { pendingArchive.count + pendingRestore.count }

  var plan: ChangePlan {
    ChangePlan(
      archive: contacts.filter { pendingArchive.contains($0.id) },
      restore: vaultEntries.filter { pendingRestore.contains($0.id) })
  }

  func load() async {
    let access = await phone.access()
    guard access == .full else {
      phase = .needsAccess(access)
      return
    }

    do {
      let vault = try await resolvedVault()
      contacts = try await phone.summaries().sorted {
        $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
      }
      scopeName = try await phone.scopeName()
      let listing = try await vault.entries()
      vaultEntries = listing.entries.sorted {
        $0.summary.displayName.localizedStandardCompare($1.summary.displayName)
          == .orderedAscending
      }
      unreadableEntries = listing.unreadable
      vaultLocation = vault.location

      pendingArchive.formIntersection(contacts.map(\.id))
      pendingRestore.formIntersection(vaultEntries.map(\.id))
      phase = .ready
    } catch {
      observer.logger.error("loading contacts and vault", error)
      phase = .failed(error.localizedDescription)
    }
  }

  func requestAccess() async {
    do {
      _ = try await phone.requestAccess()
    } catch {
      observer.logger.error("requesting contacts access", error)
      errorMessage = error.localizedDescription
    }
    await load()
  }

  func preflight() async throws -> Preflight {
    try await applier().preflight(plan)
  }

  func apply(resolutions: [String: ConflictResolution]) async -> [ApplyResult] {
    let applier: Applier
    do {
      applier = try await self.applier()
    } catch {
      observer.logger.error("opening the vault to apply", error)
      return [ApplyResult(id: "vault", name: "Vault", outcome: .failed(error.localizedDescription))]
    }
    let results = await applier.apply(plan, resolutions: resolutions)
    pendingArchive = []
    pendingRestore = []
    await load()
    return results
  }

  func saveNote(_ note: String, for entry: VaultEntry) async {
    do {
      let updated = try await resolvedVault().updateNote(note, for: entry)
      if let index = vaultEntries.firstIndex(where: { $0.id == entry.id }) {
        vaultEntries[index] = updated
      }
    } catch {
      observer.logger.error("saving note for vault entry \(entry.id)", error)
      errorMessage = "Couldn't save the note: \(error.localizedDescription)"
    }
  }

  func togglePendingArchive(_ id: ContactSummary.ID) {
    if pendingArchive.remove(id) == nil {
      pendingArchive.insert(id)
    }
  }

  func togglePendingRestore(_ id: VaultEntry.ID) {
    if pendingRestore.remove(id) == nil {
      pendingRestore.insert(id)
    }
  }

  private func resolvedVault() async throws -> any VaultStore {
    if let vault {
      return vault
    }
    let resolved = try await makeVault()
    vault = resolved
    return resolved
  }

  private func applier() async throws -> Applier {
    Applier(phone: phone, vault: try await resolvedVault(), observer: observer)
  }
}
