import Foundation

/// Password-gated developer mode: unlocked via 5 taps on the app version in
/// Einstellungen (see DeveloperUnlockSheet), then shows a 👎 feedback button
/// overlay on the main tabs and a Feedback/To-Do dashboard (DeveloperModeView).
@Observable
final class DevModeStore {
    var isActive: Bool {
        didSet { UserDefaults.standard.set(isActive, forKey: storageKey) }
    }

    /// Adds a 6th "Proben (Test)" tab showing the pharmacy Proben view
    /// alongside the regular 5 tabs, without switching the whole account kind.
    var isPharmacyTabPreviewActive: Bool {
        didSet { UserDefaults.standard.set(isPharmacyTabPreviewActive, forKey: pharmacyTabPreviewKey) }
    }

    /// Fully overrides the effective account kind to pharmacy, regardless of
    /// the real User.accountKind — RootTabView then shows just the 2-tab
    /// pharmacy app. Toggled from a button in DeveloperModeView, reachable
    /// from both account kinds.
    var isPharmacyModeActive: Bool {
        didSet { UserDefaults.standard.set(isPharmacyModeActive, forKey: pharmacyModeKey) }
    }

    private let storageKey = "com.johannesemmrich.probenfahrt.devModeActive"
    private let pharmacyTabPreviewKey = "com.johannesemmrich.probenfahrt.devPharmacyTabPreview"
    private let pharmacyModeKey = "com.johannesemmrich.probenfahrt.devPharmacyModeActive"

    init() {
        isActive = UserDefaults.standard.bool(forKey: storageKey)
        isPharmacyTabPreviewActive = UserDefaults.standard.bool(forKey: pharmacyTabPreviewKey)
        isPharmacyModeActive = UserDefaults.standard.bool(forKey: pharmacyModeKey)
    }
}
