import SwiftUI

struct ArchivedContactView: View {
  @Bindable var model: AppModel
  let entry: VaultEntry

  @State private var note: String

  init(model: AppModel, entry: VaultEntry) {
    self.model = model
    self.entry = entry
    _note = State(initialValue: entry.note)
  }

  var body: some View {
    Form {
      if !entry.summary.phoneNumbers.isEmpty || !entry.summary.emailAddresses.isEmpty {
        Section {
          ForEach(entry.summary.phoneNumbers, id: \.self) { phone in
            LabeledContent("Phone", value: phone)
          }
          ForEach(entry.summary.emailAddresses, id: \.self) { email in
            LabeledContent("Email", value: email)
          }
        }
      }
      Section {
        LabeledContent(
          "Mothballed", value: entry.archivedAt.formatted(date: .abbreviated, time: .omitted))
        if !entry.summary.organizationName.isEmpty {
          LabeledContent("Organization", value: entry.summary.organizationName)
        }
      }
      Section {
        TextField("Why you mothballed them", text: $note, axis: .vertical)
          .lineLimit(3...)
      } header: {
        Text("Note")
      } footer: {
        Text("Kept in the vault, not on the contact.")
      }
      Section {
        Toggle(
          "Restore on next apply",
          isOn: Binding(
            get: { model.pendingRestore.contains(entry.id) },
            set: { _ in model.togglePendingRestore(entry.id) }))
      }
    }
    .navigationTitle(entry.summary.displayName)
    .navigationBarTitleDisplayMode(.inline)
    .onDisappear {
      if note != entry.note {
        Task { await model.saveNote(note, for: entry) }
      }
    }
  }
}
