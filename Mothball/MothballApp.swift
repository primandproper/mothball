import Observability
import SwiftUI

@main
struct MothballApp: App {
  @State private var model: AppModel
  private let runSpike = ProcessInfo.processInfo.arguments.contains("-runSpike")

  init() {
    let pillars = ObservabilityConfig(serviceName: "mothball").bootstrap()
    let vaultObserver = makeObserver("FileVault", pillars)
    _model = State(
      initialValue: AppModel(
        phone: LivePhoneContactStore(observer: makeObserver("PhoneContactStore", pillars)),
        makeVault: { try await FileVault.resolve(observer: vaultObserver) },
        observer: makeObserver("AppModel", pillars),
        diagnostics: SpikeRunner(observer: makeObserver("SpikeRunner", pillars))))
  }

  var body: some Scene {
    WindowGroup {
      if runSpike {
        SpikeView(runner: model.diagnostics, autorun: true)
      } else {
        RootView(model: model)
      }
    }
  }
}
