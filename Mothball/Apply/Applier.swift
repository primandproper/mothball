import Foundation
import Observability

/// Carries out a `ChangePlan`. Every destructive step comes after the step that makes it safe:
/// a contact is only deleted once its archive is verified in the vault, and a phone contact being
/// replaced is only deleted once it's backed up and the replacement is on the phone.
struct Applier: Sendable {
  let phone: any PhoneContactStore
  let vault: any VaultStore
  let observer: any Observer

  func preflight(_ plan: ChangePlan) async throws -> Preflight {
    try await observer.operation { op in
      let current = try await phone.summaries()
      let currentIDs = Set(current.map(\.id))
      var preflight = Preflight()
      for contact in plan.archive {
        if currentIDs.contains(contact.id) {
          preflight.archive.append(contact)
        } else {
          preflight.missing.append(contact)
        }
      }
      for entry in plan.restore {
        let matches = ContactMatching.matches(for: entry.summary, in: current)
        if matches.isEmpty {
          preflight.restore.append(entry)
        } else {
          preflight.conflicts.append(RestoreConflict(entry: entry, matches: matches))
        }
      }
      op.set("archive.count", preflight.archive.count)
      op.set("missing.count", preflight.missing.count)
      op.set("restore.count", preflight.restore.count)
      op.set("conflict.count", preflight.conflicts.count)
      return preflight
    }
  }

  /// Re-runs the preflight so it acts on the phone as it is now, not as it was at review time. A
  /// conflict that appeared since review has no resolution and is skipped.
  func apply(_ plan: ChangePlan, resolutions: [String: ConflictResolution]) async -> [ApplyResult] {
    await observer.operation { op in
      let preflight: Preflight
      do {
        preflight = try await self.preflight(plan)
      } catch {
        op.acknowledge(error, "reading contacts before applying")
        return [
          ApplyResult(
            id: "preflight", name: "Your contacts", outcome: .failed(error.localizedDescription))
        ]
      }

      var results = preflight.missing.map {
        ApplyResult(id: $0.id, name: $0.displayName, outcome: .skipped("No longer on your phone."))
      }
      for contact in preflight.archive {
        results.append(await archive(contact, op: op))
      }
      for entry in preflight.restore {
        results.append(await restore(entry, op: op))
      }
      for conflict in preflight.conflicts {
        guard let resolution = resolutions[conflict.id] else {
          results.append(
            ApplyResult(
              id: conflict.id, name: conflict.entry.summary.displayName,
              outcome: .skipped("Now matches a contact on your phone. Review it again.")))
          continue
        }
        results.append(await resolve(conflict, with: resolution, op: op))
      }
      return results
    }
  }

  private func archive(_ contact: ContactSummary, op: any Observability.Operation) async
    -> ApplyResult
  {
    func result(_ outcome: ApplyResult.Outcome) -> ApplyResult {
      ApplyResult(id: contact.id, name: contact.displayName, outcome: outcome)
    }

    let archive: ContactArchive
    do {
      archive = try await phone.archive(contact.id)
    } catch {
      op.acknowledge(error, "archiving \(contact.id)")
      return result(.failed("Couldn't read it from your phone: \(error.localizedDescription)"))
    }

    let entry: VaultEntry
    do {
      entry = try await vault.save(archive, note: "", to: .mothballed)
    } catch {
      op.acknowledge(error, "saving \(contact.id) to the vault")
      return result(.failed("Couldn't save it to the vault: \(error.localizedDescription)"))
    }

    do {
      try await phone.delete(contact.id)
    } catch {
      op.acknowledge(error, "deleting \(contact.id) after archiving")
      do {
        try await vault.discard(entry)
      } catch {
        op.acknowledge(error, "discarding vault entry \(entry.id) after a failed delete")
        return result(
          .failed(
            "Saved to the vault but couldn't remove it from your phone, and the vault copy "
              + "couldn't be discarded, so it's in both places."))
      }
      return result(
        .failed("Couldn't remove it from your phone: \(error.localizedDescription)"))
    }
    return result(.archived)
  }

  private func restore(_ entry: VaultEntry, op: any Observability.Operation) async -> ApplyResult {
    func result(_ outcome: ApplyResult.Outcome) -> ApplyResult {
      ApplyResult(id: entry.id, name: entry.summary.displayName, outcome: outcome)
    }

    let outcome: RestoreOutcome
    do {
      outcome = try await phone.restore(vault.archive(for: entry))
    } catch {
      op.acknowledge(error, "restoring vault entry \(entry.id)")
      return result(.failed("Couldn't restore it: \(error.localizedDescription)"))
    }

    do {
      try await vault.markRestored(entry)
    } catch {
      op.acknowledge(error, "marking vault entry \(entry.id) restored")
      return result(
        .failed(
          "Restored to your phone, but the vault still lists it: \(error.localizedDescription)"))
    }
    return result(.restored(differences: outcome.differences))
  }

  private func resolve(
    _ conflict: RestoreConflict, with resolution: ConflictResolution,
    op: any Observability.Operation
  ) async -> ApplyResult {
    let entry = conflict.entry
    func result(_ outcome: ApplyResult.Outcome) -> ApplyResult {
      ApplyResult(id: entry.id, name: entry.summary.displayName, outcome: outcome)
    }

    switch resolution {
    case .keepBoth:
      return await restore(entry, op: op)

    case .keepPhone:
      do {
        try await vault.markRestored(entry)
      } catch {
        op.acknowledge(error, "marking vault entry \(entry.id) restored")
        return result(.failed("Couldn't update the vault: \(error.localizedDescription)"))
      }
      return result(.keptPhoneVersion)

    case .replace:
      for match in conflict.matches {
        do {
          let backup = try await phone.archive(match.id)
          _ = try await vault.save(
            backup, note: "Replaced by the mothballed copy of \(entry.summary.displayName).",
            to: .restored)
        } catch {
          op.acknowledge(error, "backing up \(match.id) before replacing it")
          return result(
            .failed(
              "Couldn't back up \(match.displayName) before replacing it, so nothing changed: "
                + error.localizedDescription))
        }
      }

      let restored = await restore(entry, op: op)
      guard case .restored(let differences) = restored.outcome else { return restored }

      for match in conflict.matches {
        do {
          try await phone.delete(match.id)
        } catch {
          op.acknowledge(error, "deleting replaced contact \(match.id)")
          return result(
            .failed(
              "Restored, but couldn't remove \(match.displayName) from your phone, so both are "
                + "there. A backup of it is in Restored."))
        }
      }
      return result(.replaced(differences: differences))
    }
  }
}
