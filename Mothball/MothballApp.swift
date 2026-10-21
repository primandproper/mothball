import Observability
import SwiftUI

@main
struct MothballApp: App {
  private let pillars = ObservabilityConfig(serviceName: "mothball").bootstrap()

  var body: some Scene {
    WindowGroup {
      SpikeView(
        runner: SpikeRunner(observer: makeObserver("SpikeRunner", pillars)),
        autorun: ProcessInfo.processInfo.arguments.contains("-runSpike"))
    }
  }
}
