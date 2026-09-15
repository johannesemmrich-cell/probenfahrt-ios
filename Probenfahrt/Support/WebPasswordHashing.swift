import CryptoKit
import Foundation

/// Hashes web-login passwords before they ever reach CloudKit (BACKLOG #5).
/// The exact scheme (`SHA256("pepper:password")`, lowercase hex) must match
/// `hashWebPassword` in web/worker-app/src/index.js byte-for-byte, or a
/// password set here will never match at login time.
enum WebPasswordHashing {
    static func hash(_ password: String) -> String {
        let input = "\(WebPasswordPepper.value):\(password)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
