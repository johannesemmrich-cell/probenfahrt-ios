import Foundation

/// Tracks which local `User` is "logged in" (onboarding is just a name/abbreviation +
/// join-code check, not real auth — see BACKLOG #4).
@Observable
final class SessionStore {
    private(set) var currentUserID: UUID?
    /// True only for a session started via the onboarding "Demo-Modus"
    /// button — lets Einstellungen keep showing "Als Admin anzeigen" for
    /// demo/review sessions even though the real Entwicklung section stays
    /// hidden for everyone else until the dev password unlocks it.
    private(set) var isDemoSession = false
    private let storageKey = "com.johannesemmrich.probenfahrt.currentUserID"
    private let demoSessionKey = "com.johannesemmrich.probenfahrt.isDemoSession"

    init() {
        if let raw = UserDefaults.standard.string(forKey: storageKey) {
            currentUserID = UUID(uuidString: raw)
        }
        isDemoSession = UserDefaults.standard.bool(forKey: demoSessionKey)
    }

    var isOnboarded: Bool { currentUserID != nil }

    func setCurrentUser(id: UUID, isDemo: Bool = false) {
        currentUserID = id
        UserDefaults.standard.set(id.uuidString, forKey: storageKey)
        isDemoSession = isDemo
        UserDefaults.standard.set(isDemo, forKey: demoSessionKey)
    }

    func signOut() {
        currentUserID = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
        isDemoSession = false
        UserDefaults.standard.removeObject(forKey: demoSessionKey)
    }
}
