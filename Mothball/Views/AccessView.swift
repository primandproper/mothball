import SwiftUI
import UIKit

struct AccessView: View {
  let access: ContactAccess
  let requestAccess: () async -> Void

  @Environment(\.openURL) private var openURL

  var body: some View {
    ContentUnavailableView {
      Label("Mothball needs your contacts", systemImage: "person.crop.circle.badge.questionmark")
    } description: {
      Text(explanation)
    } actions: {
      if access == .notDetermined {
        Button("Allow Access") { Task { await requestAccess() } }
          .buttonStyle(.borderedProminent)
      } else if let settings = URL(string: UIApplication.openSettingsURLString) {
        Button("Open Settings") { openURL(settings) }
          .buttonStyle(.borderedProminent)
      }
    }
  }

  private var explanation: String {
    switch access {
    case .notDetermined:
      "Mothball archives the contacts you pick and removes them from your phone, so it needs to "
        + "read and change your contacts."
    case .limited:
      "Mothball only works with full access: it can't see contacts it wasn't given, so it can't "
        + "tell you who's already on your phone. Choose Full Access under Contacts in Settings."
    case .denied, .full:
      "Contacts access is turned off. Turn it on under Contacts in Settings."
    }
  }
}
