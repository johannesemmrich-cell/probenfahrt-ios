import Foundation

/// Password-gated developer mode: unlocked via 5 taps on the app version in
/// Einstellungen (see DeveloperUnlockSheet), then shows a 👎 feedback button
/// overlay on the main tabs and a Feedback/To-Do dashboard (DeveloperModeView).
@Observable
final class DevModeStore {
    var isActive: Bool {
        didSet { UserDefaults.standard.set(isActive, forKey: storageKey) }
    }

    /// Grants full Haupt-Admin rights everywhere `isFullAdmin`/
    /// `isEffectiveAdmin` is checked — a DevMode-gated equivalent of the
    /// standalone "Als Admin anzeigen" toggle in Einstellungen, added
    /// alongside it (not replacing it yet) so the preview still works once
    /// that older, ungated toggle is eventually removed (Backlog #2).
    var isAdminPreviewActive: Bool {
        didSet { UserDefaults.standard.set(isAdminPreviewActive, forKey: adminPreviewKey) }
    }

    private let storageKey = "com.johannesemmrich.probenfahrt.devModeActive"
    private let adminPreviewKey = "com.johannesemmrich.probenfahrt.devAdminPreviewActive"

    init() {
        isActive = UserDefaults.standard.bool(forKey: storageKey)
        isAdminPreviewActive = UserDefaults.standard.bool(forKey: adminPreviewKey)
    }
}
