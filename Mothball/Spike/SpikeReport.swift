import Foundation

struct SpikeReport: Codable, Sendable {
  let startedAt: Date
  var finishedAt: Date?
  var steps: [SpikeStep]
}

struct SpikeStep: Codable, Identifiable, Sendable {
  enum Outcome: String, Codable, Sendable {
    case pass
    case fail
    /// The operation succeeded but fields changed along the way.
    case lossy
    case info
    case skip
  }

  var id: String { name }
  let name: String
  let outcome: Outcome
  let details: [String]
}

extension Error {
  /// Domain and code alongside the message, since Contacts errors are only diagnosable by code.
  var spikeDescription: String {
    let ns = self as NSError
    return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
  }
}
