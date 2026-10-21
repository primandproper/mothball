import Foundation

/// Finds phone contacts that look like the same person as an archived one. Restored contacts can
/// get new identifiers, so matching goes by phone number or email address instead.
enum ContactMatching {
  static func matches(for target: ContactSummary, in candidates: [ContactSummary])
    -> [ContactSummary]
  {
    let phones = Set(target.phoneNumbers.compactMap(normalizedPhone))
    let emails = Set(target.emailAddresses.compactMap(normalizedEmail))
    guard !phones.isEmpty || !emails.isEmpty else { return [] }
    return candidates.filter { candidate in
      !phones.isDisjoint(with: candidate.phoneNumbers.compactMap(normalizedPhone))
        || !emails.isDisjoint(with: candidate.emailAddresses.compactMap(normalizedEmail))
    }
  }

  /// Digits only, keeping the last 10 so "+1 (555) 010-2000" and "555-010-2000" compare equal.
  /// Anything under 7 digits is too ambiguous to match on.
  static func normalizedPhone(_ raw: String) -> String? {
    let digits = raw.filter { $0.isASCII && $0.isNumber }
    guard digits.count >= 7 else { return nil }
    return String(digits.suffix(10))
  }

  static func normalizedEmail(_ raw: String) -> String? {
    let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return email.isEmpty ? nil : email
  }
}
