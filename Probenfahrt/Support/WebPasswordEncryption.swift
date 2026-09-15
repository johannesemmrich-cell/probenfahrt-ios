import CryptoKit
import Foundation

/// Encrypts web-login passwords before they reach CloudKit (reversible,
/// unlike the SHA-256 hash used earlier on 2026-09-15 — an admin needs to
/// be able to view a member's password again, not just verify it's set).
///
/// AES-256-GCM with a **deterministic** nonce derived from
/// `SHA256("iv:" + key + ":" + password)` (first 12 bytes) instead of a
/// random one - keeps "same password -> same ciphertext" (needed so the
/// Worker can find a user via an exact-match CloudKit query, same reason
/// the old hash had no per-user salt) while never reusing a (key, nonce)
/// pair for two *different* plaintexts, which is the actual GCM hazard.
/// Stored as `nonce (12 bytes) || ciphertext+tag`, base64 - exactly
/// CryptoKit's `AES.GCM.SealedBox.combined` layout, so it round-trips
/// without manual parsing. Must match `encryptWebPassword`/
/// `decryptWebPassword` in web/worker-app/src/index.js byte-for-byte.
enum WebPasswordEncryption {
    private static var key: SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data(WebPasswordEncryptionKey.value.utf8)))
    }

    private static func derivedNonce(for password: String) throws -> AES.GCM.Nonce {
        let input = "iv:\(WebPasswordEncryptionKey.value):\(password)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return try AES.GCM.Nonce(data: Data(digest.prefix(12)))
    }

    static func encrypt(_ password: String) -> String {
        guard let nonce = try? derivedNonce(for: password),
              let sealed = try? AES.GCM.seal(Data(password.utf8), using: key, nonce: nonce),
              let combined = sealed.combined else {
            return ""
        }
        return combined.base64EncodedString()
    }

    static func decrypt(_ encoded: String) -> String? {
        guard let data = Data(base64Encoded: encoded),
              let sealedBox = try? AES.GCM.SealedBox(combined: data),
              let plaintext = try? AES.GCM.open(sealedBox, using: key) else {
            return nil
        }
        return String(data: plaintext, encoding: .utf8)
    }
}
