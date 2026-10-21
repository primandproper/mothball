import SwiftUI

struct RootView: View {
  @Bindable var model: AppModel
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      switch model.phase {
      case .loading:
        ProgressView()
      case .needsAccess(let access):
        AccessView(access: access) { await model.requestAccess() }
      case .failed(let message):
        ContentUnavailableView {
          Label("Couldn't load your contacts", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button("Try Again") { Task { await model.load() } }
        }
      case .ready:
        MainView(model: model)
      }
    }
    .task { await model.load() }
    // Picks up changes made elsewhere (Contacts, Settings, another device's vault writes).
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task { await model.load() }
      }
    }
    .alert(
      "Something went wrong",
      isPresented: Binding(
        get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? "")
    }
  }
}

private struct MainView: View {
  @Bindable var model: AppModel
  @State private var showingReview = false
  @State private var showingDiagnostics = false

  var body: some View {
    TabView {
      Tab("Contacts", systemImage: "person.crop.circle") {
        NavigationStack {
          ContactsView(model: model)
            .toolbar { toolbar }
        }
      }
      Tab("Mothballed", systemImage: "archivebox") {
        NavigationStack {
          MothballedView(model: model)
            .toolbar { toolbar }
        }
      }
      .badge(model.vaultEntries.count)
    }
    .sheet(isPresented: $showingReview) {
      ReviewView(model: model)
    }
    .sheet(isPresented: $showingDiagnostics) {
      SpikeView(runner: model.diagnostics, autorun: false)
    }
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Button("Review (\(model.pendingCount))") { showingReview = true }
        .disabled(model.pendingCount == 0)
    }
    ToolbarItem(placement: .secondaryAction) {
      Button("Diagnostics", systemImage: "stethoscope") { showingDiagnostics = true }
    }
  }
}
