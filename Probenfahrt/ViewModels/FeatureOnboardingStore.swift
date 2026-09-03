import Foundation

/// Tracks whether the feature-tour (FeatureOnboardingView) has been shown
/// once already — not to be confused with OnboardingContainerView, which is
/// the group-join step. Shown automatically the first time after joining,
/// replayable any time from Einstellungen.
@Observable
final class FeatureOnboardingStore {
    var hasSeenFeatureOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasSeenFeatureOnboarding, forKey: storageKey) }
    }

    private let storageKey = "com.johannesemmrich.probenfahrt.hasSeenFeatureOnboarding"

    init() {
        hasSeenFeatureOnboarding = UserDefaults.standard.bool(forKey: storageKey)
    }
}
