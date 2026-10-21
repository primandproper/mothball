import SwiftUI

struct ReviewView: View {
  @Bindable var model: AppModel
  @Environment(\.dismiss) private var dismiss

  private enum Stage {
    case checking
    case ready(Preflight)
    case applying
    case done([ApplyResult])
    case failed(String)
  }

  @State private var stage: Stage = .checking
  @State private var resolutions: [String: ConflictResolution] = [:]
  @State private var acceptedLocalVault = false

  var body: some View {
    NavigationStack {
      content
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            if case .done = stage {
              Button("Done") { dismiss() }
            } else {
              Button("Cancel") { dismiss() }
                .disabled(isApplying)
            }
          }
        }
    }
    .interactiveDismissDisabled(isApplying)
    .task { await check() }
  }

  @ViewBuilder
  private var content: some View {
    switch stage {
    case .checking:
      ProgressView("Checking your contacts")
    case .applying:
      ProgressView("Applying changes")
    case .failed(let message):
      ContentUnavailableView {
        Label("Couldn't check your contacts", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try Again") { Task { await check() } }
      }
    case .ready(let preflight):
      ready(preflight)
    case .done(let results):
      List(results) { result in
        ResultRow(result: result)
      }
    }
  }

  private func ready(_ preflight: Preflight) -> some View {
    let needsLocalConsent = model.vaultLocation == .local && !preflight.archive.isEmpty
    return List {
      if !preflight.archive.isEmpty {
        Section("Mothball (\(preflight.archive.count))") {
          ForEach(preflight.archive) { Text($0.displayName) }
        }
      }
      if !preflight.restore.isEmpty {
        Section("Restore (\(preflight.restore.count))") {
          ForEach(preflight.restore) { Text($0.summary.displayName) }
        }
      }
      if !preflight.conflicts.isEmpty {
        Section {
          ForEach(preflight.conflicts) { conflict in
            ConflictRow(conflict: conflict, resolution: resolution(for: conflict.id))
          }
        } header: {
          Text("Already on your phone (\(preflight.conflicts.count))")
        } footer: {
          Text("These share a phone number or email address with a contact on your phone.")
        }
      }
      if !preflight.missing.isEmpty {
        Section {
          ForEach(preflight.missing) { Text($0.displayName) }
        } header: {
          Text("Skipped")
        } footer: {
          Text("No longer on your phone, so there's nothing to mothball.")
        }
      }
      if needsLocalConsent {
        Section {
          Toggle(
            "I understand the vault is only on this phone, because iCloud Drive is off",
            isOn: $acceptedLocalVault)
        }
      }
      Section {
        Button("Apply Changes") { Task { await apply() } }
          .frame(maxWidth: .infinity)
          .disabled(
            (preflight.archive.isEmpty && preflight.restore.isEmpty && preflight.conflicts.isEmpty)
              || (needsLocalConsent && !acceptedLocalVault))
      }
    }
  }

  private var title: String {
    if case .done = stage {
      return "Results"
    }
    return "Review"
  }

  private var isApplying: Bool {
    if case .applying = stage {
      return true
    }
    return false
  }

  private func resolution(for id: String) -> Binding<ConflictResolution> {
    Binding(
      get: { resolutions[id] ?? .default },
      set: { resolutions[id] = $0 })
  }

  private func check() async {
    stage = .checking
    do {
      let preflight = try await model.preflight()
      for conflict in preflight.conflicts where resolutions[conflict.id] == nil {
        resolutions[conflict.id] = .default
      }
      stage = .ready(preflight)
    } catch {
      stage = .failed(error.localizedDescription)
    }
  }

  private func apply() async {
    stage = .applying
    stage = .done(await model.apply(resolutions: resolutions))
  }
}

private struct ConflictRow: View {
  let conflict: RestoreConflict
  @Binding var resolution: ConflictResolution

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(conflict.entry.summary.displayName)
      Text("Matches " + conflict.matches.map(\.displayName).joined(separator: ", "))
        .font(.caption)
        .foregroundStyle(.secondary)
      Picker("Resolution", selection: $resolution) {
        ForEach(ConflictResolution.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.menu)
      .labelsHidden()
    }
  }
}

private struct ResultRow: View {
  let result: ApplyResult

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Label(result.name, systemImage: symbol)
        .foregroundStyle(color)
      if let detail {
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var symbol: String {
    switch result.outcome {
    case .archived: "archivebox.fill"
    case .restored, .replaced: "arrow.uturn.backward.circle.fill"
    case .keptPhoneVersion: "iphone"
    case .skipped: "forward.fill"
    case .failed: "xmark.octagon.fill"
    }
  }

  private var color: Color {
    switch result.outcome {
    case .archived, .restored, .replaced, .keptPhoneVersion: .primary
    case .skipped: .secondary
    case .failed: .red
    }
  }

  private var detail: String? {
    switch result.outcome {
    case .archived:
      "Mothballed."
    case .restored(let differences):
      differences.isEmpty
        ? "Restored." : "Restored, but these fields changed: " + differences.joined(separator: "; ")
    case .replaced(let differences):
      differences.isEmpty
        ? "Replaced the phone's version, which is backed up in Restored."
        : "Replaced, but these fields changed: " + differences.joined(separator: "; ")
    case .keptPhoneVersion:
      "Kept the phone's version. The mothballed copy moved to Restored."
    case .skipped(let reason), .failed(let reason):
      reason
    }
  }
}
