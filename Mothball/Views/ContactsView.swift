import SwiftUI

struct ContactsView: View {
  @Bindable var model: AppModel
  @State private var search = ""

  var body: some View {
    List {
      ForEach(sections, id: \.title) { section in
        Section(section.title) {
          ForEach(section.contacts) { contact in
            ContactRow(
              contact: contact, pending: model.pendingArchive.contains(contact.id)
            ) {
              model.togglePendingArchive(contact.id)
            }
          }
        }
      }
    }
    .searchable(text: $search)
    .overlay {
      if model.contacts.isEmpty {
        ContentUnavailableView(
          "No Contacts", systemImage: "person.crop.circle",
          description: Text("There are no contacts in \(model.scopeName)."))
      } else if sections.isEmpty {
        ContentUnavailableView.search(text: search)
      }
    }
    .navigationTitle(model.scopeName)
  }

  private var sections: [(title: String, contacts: [ContactSummary])] {
    let filtered = search.isEmpty ? model.contacts : model.contacts.filter(matchesSearch)
    let grouped = Dictionary(grouping: filtered, by: \.sectionTitle)
    return grouped.keys.sorted { lhs, rhs in
      // "#" sorts after the letters, matching Contacts.app.
      lhs == "#" ? false : rhs == "#" ? true : lhs < rhs
    }.map { ($0, grouped[$0] ?? []) }
  }

  private func matchesSearch(_ contact: ContactSummary) -> Bool {
    ([contact.displayName] + contact.phoneNumbers + contact.emailAddresses)
      .contains { $0.localizedStandardContains(search) }
  }
}

private struct ContactRow: View {
  let contact: ContactSummary
  let pending: Bool
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      HStack {
        VStack(alignment: .leading) {
          Text(contact.displayName)
            .foregroundStyle(.primary)
          if let detail = contact.detail {
            Text(detail)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        Image(systemName: pending ? "archivebox.fill" : "circle")
          .foregroundStyle(pending ? .orange : .secondary)
          .imageScale(.large)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityValue(pending ? "Will be mothballed" : "")
    .accessibilityHint(
      pending ? "Removes it from the changes to apply" : "Marks it for mothballing")
  }
}
