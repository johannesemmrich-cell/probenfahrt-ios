import Foundation

/// Symmetric key material for `WebPasswordEncryption`, so an admin can view
/// a member's web-access password again (2026-09-15 decision — replaces the
/// one-way hash from earlier the same day). Must be identical to the
/// `WEB_PASSWORD_ENCRYPTION_KEY` secret set on the web/worker-app Cloudflare
/// Worker, or passwords set here won't decrypt/match there.
/// Compiled into the app bundle, so not truly secret from `strings` on the
/// binary — same deliberately-simple security posture as AdminCode.value,
/// not a real secret-management setup.
enum WebPasswordEncryptionKey {
    static let value = "f0f9cadfc06d44427f4f77f0b285499c852348e558f0a33ad503a31c91bfa9e5"
}
