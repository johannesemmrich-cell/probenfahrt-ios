import Foundation
import CryptoKit

/// Shared developer-mode password check (SHA-256 hash only — the password
/// itself is never stored). Used both by the explicit unlock sheet
/// (DeveloperUnlockSheet) and as a shortcut in the onboarding join-code
/// field: typing this password there logs straight into the app with Dev
/// Mode already active.
enum DevPassword {
    private static let hash = "5187f60ecb928fbbdfd417d75bda193f441dce05a2309f7494770a584f59e27e"

    static func matches(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        return hex == hash
    }
}
