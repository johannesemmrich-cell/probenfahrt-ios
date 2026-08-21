import Foundation

/// The code any team member can enter at the bottom of Einstellungen to
/// promote themselves straight to Haupt-Admin. Deliberately plain/simple for
/// now — unlike DevPassword — matching the other simple join-style codes
/// (LABOR2026/PROBEN2026) until Backlog #2 replaces all of this with real
/// auth. Not a secret worth hashing yet; the value itself is expected to
/// change once this becomes more than a prototype mechanism.
enum AdminCode {
    static let value = "Admin"

    static func matches(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.caseInsensitiveCompare(value) == .orderedSame
    }
}
