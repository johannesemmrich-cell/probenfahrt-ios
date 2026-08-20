import Foundation

/// Tracks which local `User` is "logged in" (onboarding is just a name/abbreviation +
/// join-code check, not real auth — see BACKLOG #4).
@Observable
final class SessionStore {
    private(set) var currentUserID: UUID?
    private let storageKey = "com.johannesemmrich.probenfahrt.currentUserID"

    init() {
        if let raw = UserDefaults.standard.string(forKey: storageKey) {
            currentUserID = UUID(uuidString: raw)
        }
    }

    var isOnboarded: Bool { currentUserID != nil }

    func setCurrentUser(id: UUID) {
        currentUserID = id
        UserDefaults.standard.set(id.uuidString, forKey: storageKey)
    }

    func signOut() {
        currentUserID = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
