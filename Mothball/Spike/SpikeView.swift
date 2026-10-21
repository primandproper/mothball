import SwiftUI

struct SpikeView: View {
  let runner: SpikeRunner
  let autorun: Bool

  @State private var report: SpikeReport?
  @State private var running = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text(
            "Creates, archives, deletes and restores a throwaway contact, then deletes the contact "
              + "named \"Mothball NoteTest\" if one exists. No other contact is touched."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
        if let report {
          ForEach(report.steps) { step in
            Section {
              ForEach(Array(step.details.enumerated()), id: \.offset) { _, detail in
                Text(detail).font(.caption.monospaced()).textSelection(.enabled)
              }
            } header: {
              Label(step.name, systemImage: symbol(for: step.outcome))
                .foregroundStyle(color(for: step.outcome))
            }
          }
        }
      }
      .navigationTitle("Round-trip spike")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          if running {
            ProgressView()
          } else {
            Button("Run") { Task { await run() } }
          }
        }
        if report != nil {
          ToolbarItem(placement: .secondaryAction) {
            ShareLink(item: SpikeRunner.reportURL)
          }
        }
      }
      .task {
        if autorun {
          await run()
        }
      }
    }
  }

  private func run() async {
    running = true
    report = await runner.run()
    running = false
  }

  private func symbol(for outcome: SpikeStep.Outcome) -> String {
    switch outcome {
    case .pass: "checkmark.circle.fill"
    case .fail: "xmark.octagon.fill"
    case .lossy: "exclamationmark.triangle.fill"
    case .info: "info.circle.fill"
    case .skip: "forward.fill"
    }
  }

  private func color(for outcome: SpikeStep.Outcome) -> Color {
    switch outcome {
    case .pass: .green
    case .fail: .red
    case .lossy: .orange
    case .info: .blue
    case .skip: .secondary
    }
  }
}
