import Foundation

/// `CNContactVCardSerialization` drops the contact photo, so the portable vCard copy gets it added
/// back by hand.
enum VCardPhoto {
  private static let maxLineLength = 75

  static func inject(_ photo: Data, into vCard: Data) -> Data {
    guard
      var text = String(data: vCard, encoding: .utf8),
      !text.contains("\nPHOTO"),
      let end = text.range(of: "END:VCARD", options: .backwards)
    else { return vCard }

    let newline = text.contains("\r\n") ? "\r\n" : "\n"
    let type = photo.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "PNG" : "JPEG"
    let line = "PHOTO;ENCODING=b;TYPE=\(type):\(photo.base64EncodedString())"
    text.insert(contentsOf: fold(line, newline: newline) + newline, at: end.lowerBound)
    return Data(text.utf8)
  }

  /// vCard 3.0 folds lines longer than 75 octets; each continuation line starts with one space.
  /// The PHOTO line is ASCII, so characters and octets line up.
  static func fold(_ line: String, newline: String) -> String {
    var lines: [Substring] = []
    var rest = Substring(line)
    var limit = maxLineLength
    while rest.count > limit {
      lines.append(rest.prefix(limit))
      rest = rest.dropFirst(limit)
      limit = maxLineLength - 1
    }
    lines.append(rest)
    return lines.joined(separator: newline + " ")
  }
}
