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
    func allUsers(inGroup groupID: UUID) async throws -> [User]
    func user(id: UUID) async throws -> User?
    func isAbbreviationTaken(_ abbreviation: String, inGroup groupID: UUID) async throws -> Bool
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
    func deleteUser(id: UUID, bypassLastAdminGuard: Bool) async throws
}
