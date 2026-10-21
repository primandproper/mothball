import SwiftUI

struct MothballedView: View {
  @Bindable var model: AppModel

  var body: some View {
    List {
      if model.vaultLocation == .local {
        Section {
          Label(
            "iCloud Drive is off, so the vault is only on this phone. Deleting the app or losing "
              + "the phone loses every mothballed contact.",
            systemImage: "exclamationmark.icloud"
          )
          .foregroundStyle(.orange)
        }
      }
      if !model.unreadableEntries.isEmpty {
        Section {
          Label(
            "\(model.unreadableEntries.count) vault entries couldn't be read: "
              + model.unreadableEntries.joined(separator: ", "),
            systemImage: "exclamationmark.triangle"
          )
          .foregroundStyle(.red)
        }
      }
      ForEach(model.vaultEntries) { entry in
        let pending = model.pendingRestore.contains(entry.id)
        NavigationLink(value: entry) {
          HStack {
            VStack(alignment: .leading) {
              Text(entry.summary.displayName)
              Text(entry.archivedAt, format: .dateTime.year().month().day())
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if pending {
              Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Will be restored")
            }
          }
        }
        .swipeActions {
          Button(pending ? "Don't Restore" : "Restore") {
            model.togglePendingRestore(entry.id)
          }
          .tint(pending ? .gray : .green)
        }
      }
    }
    .overlay {
      if model.vaultEntries.isEmpty {
        ContentUnavailableView(
          "Nothing Mothballed", systemImage: "archivebox",
          description: Text("Contacts you mothball show up here."))
      }
    }
    .navigationTitle("Mothballed")
    .navigationDestination(for: VaultEntry.self) { entry in
      ArchivedContactView(model: model, entry: entry)
    }
  }
}
