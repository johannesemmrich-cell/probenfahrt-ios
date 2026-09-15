import Foundation

/// Server-side-style pepper mixed into every `User.webPasswordHash` hash
/// (see WebPasswordHashing) so the CloudKit Dashboard never shows a directly
/// usable password (BACKLOG #5). Must be identical to the
/// `WEB_PASSWORD_PEPPER` secret set on the web/worker-app Cloudflare Worker,
/// or hashes computed here and there won't match and every web login fails.
/// Compiled into the app bundle, so not truly secret from `strings` on the
/// binary — same deliberately-simple security posture as AdminCode.value,
/// not a real secret-management setup.
enum WebPasswordPepper {
    static let value = "8bee95ad286b195cab692636d73888933be871ec8a0c61a52fe7d1db9ffc1a27"
}
