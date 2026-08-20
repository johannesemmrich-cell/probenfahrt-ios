import Foundation

/// Persists whether the Proben-tab access code has already been entered
/// successfully on this device, so it isn't re-asked on every tab switch.
/// TODO(Backlog #1): replace with real code-based access provisioning.
@Observable
final class SamplesAccessStore {
    var isUnlocked: Bool {
        didSet { UserDefaults.standard.set(isUnlocked, forKey: storageKey) }
    }

    private let storageKey = "com.johannesemmrich.probenfahrt.samplesUnlocked"

    init() {
        isUnlocked = UserDefaults.standard.bool(forKey: storageKey)
    }
}
