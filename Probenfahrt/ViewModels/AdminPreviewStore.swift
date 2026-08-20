import Foundation

/// Backs the clearly-labeled "Als Admin anzeigen" dev toggle in Einstellungen.
/// Lets any test user preview admin-only views without real role enforcement.
/// TODO(Backlog #4): remove once real auth/role enforcement lands; admin views
/// must then depend solely on `User.role`, not this override.
@Observable
final class AdminPreviewStore {
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: storageKey) }
    }

    private let storageKey = "com.johannesemmrich.probenfahrt.adminPreviewEnabled"

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: storageKey)
    }
}
