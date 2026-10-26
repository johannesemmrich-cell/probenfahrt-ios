import Foundation

struct GroupJoinResult {
    let group: TeamGroup
    let accountKind: AccountKind
}

enum UserRepositoryError: Error {
    /// Deleting this user would leave the group with zero admins — refused,
    /// since there's no in-app way to promote a new one (Backlog #2).
    case cannotRemoveLastAdmin
}

/// Pure guard used by `deleteUser`: refuse only when removing this specific
/// user would zero out the group's admins.
func canRemoveUser(_ user: User, adminCountInGroup: Int) -> Bool {
    user.role != .admin || adminCountInGroup > 1
}

@MainActor
protocol UserRepository {
    /// Active members only (excludes soft-deleted/`isRemoved` users) — the
    /// roster for onboarding, admin counts, Kürzel-Eindeutigkeit and every
    /// "current members" list.
    func allUsers(inGroup groupID: UUID) async throws -> [User]
    /// Active members plus previously removed ones — needed wherever a past
    /// `SurveyEntry` must still resolve a name/abbreviation (day detail,
    /// "Vergangene Umfragen", PDF Monatsauswertung).
    func allUsersIncludingRemoved(inGroup groupID: UUID) async throws -> [User]
    /// Nil only when CloudKit positively reports the record doesn't exist
    /// (`CKError.unknownItem`) — network/iCloud errors are thrown instead,
    /// so callers (RootTabView) can keep the session instead of falsely
    /// signing the member out ("Mitglieder fliegen aus der App").
    func user(id: UUID) async throws -> User?
    func isAbbreviationTaken(_ abbreviation: String, inGroup groupID: UUID) async throws -> Bool
    /// Looks up the member a reconnect login ("GruppenCode-Code", see
    /// `ReconnectCode`) should reattach to. Searches removed members too —
    /// a self-left member keeps their code and may return; an admin-removed
    /// member had the code revoked by `deleteUser`, so they never match.
    func userByReconnectCode(_ code: String, inGroup groupID: UUID) async throws -> User?
    /// Uniqueness spans the whole group INCLUDING removed members (they keep
    /// their code for reconnecting), unlike Kürzel uniqueness which only
    /// checks the active roster.
    func isReconnectCodeTaken(_ code: String, inGroup groupID: UUID, excluding userID: UUID?) async throws -> Bool
    /// Saves Name, Kürzel AND Wiedereinstiegs-Code in ONE record save.
    /// Deliberately not two sequential calls (updateUser + a separate
    /// code setter): back-to-back saves on the same record produced
    /// CloudKit "client oplock" conflicts in practice (stale change tag
    /// on the second save). Pass reconnectCode nil/invalid to clear it;
    /// stored normalized (see `ReconnectCode`).
    func updateProfile(id: UUID, name: String, abbreviation: String, reconnectCode: String?) async throws
    /// Clears `isRemoved` again when a self-left member reconnects via their
    /// Wiedereinstiegs-Code — same UUID, so Fahrten/Umfragen/Kalender history
    /// reattaches instead of a duplicate account starting at zero.
    func reactivateUser(id: UUID) async throws
    /// Resolves either a group's regular join code or its pharmacy join code,
    /// reporting which one matched so onboarding can branch accordingly.
    func resolveJoinCode(_ code: String) async throws -> GroupJoinResult?
    @discardableResult
    func createUser(name: String, abbreviation: String, groupID: UUID) async throws -> User
    @discardableResult
    func createPharmacyUser(firmName: String, groupID: UUID) async throws -> User
    func updateUser(id: UUID, name: String, abbreviation: String) async throws
    /// Used both for self-promotion to Haupt-Admin (via the Admin-Code field
    /// in Einstellungen) and Vice-Admin promotion/demotion (via
    /// MemberDetailView). Refuses to demote a group's last Haupt-Admin, same
    /// guard as `deleteUser` — unless `bypassLastAdminGuard` is set, which
    /// only the DevMode/Admin-Vorschau escape hatch in MemberDetailView ever
    /// passes.
    func setRole(id: UUID, role: UserRole, bypassLastAdminGuard: Bool) async throws
    /// Soft delete: marks the user `isRemoved` and clears their web password
    /// (so they can no longer log into app.mediproben.com) instead of
    /// deleting the CloudKit record outright. Past `SurveyEntry` rows keep
    /// referencing this `id`, so they stay attributable in historical views;
    /// `allUsers` excludes the user from every active roster and
    /// Kürzel-Eindeutigkeit check, freeing their name/Kürzel for reuse.
    /// `revokeReconnectCode` distinguishes the two removal paths: an admin
    /// removing a member passes true (the member must not let themselves
    /// back in via Wiedereinstiegs-Code), self-leave in Einstellungen passes
    /// false (the member may return anytime with their code).
    func deleteUser(id: UUID, bypassLastAdminGuard: Bool, revokeReconnectCode: Bool) async throws
    /// Admin-assigned password for the web check-in login (mediproben.com,
    /// see MemberDetailView) - pass nil/empty to clear it.
    func setWebPassword(_ password: String?, for id: UUID) async throws
    /// Web login (mediproben.com) has no group context to scope by - it's a
    /// single global password lookup - so uniqueness must be checked across
    /// every user in the container, not just one group, or two different
    /// teams' admins could still collide.
    func isWebPasswordTaken(_ password: String, excluding userID: UUID) async throws -> Bool
}
