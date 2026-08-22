import Foundation
import SwiftData

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

@MainActor
final class SwiftDataUserRepository: UserRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func allUsers(inGroup groupID: UUID) async throws -> [User] {
        try context.fetch(FetchDescriptor<User>(predicate: #Predicate<User> { $0.groupID == groupID }))
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func user(id: UUID) async throws -> User? {
        try context.fetch(FetchDescriptor<User>(predicate: #Predicate<User> { $0.id == id })).first
    }

    func isAbbreviationTaken(_ abbreviation: String, inGroup groupID: UUID) async throws -> Bool {
        let normalized = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let users = try context.fetch(FetchDescriptor<User>(predicate: #Predicate<User> { $0.groupID == groupID }))
        return users.contains { $0.abbreviation.lowercased() == normalized }
    }

    func resolveJoinCode(_ code: String) async throws -> GroupJoinResult? {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        let groups = try context.fetch(FetchDescriptor<TeamGroup>())
        for group in groups {
            if group.joinCode.lowercased() == normalized {
                return GroupJoinResult(group: group, accountKind: .labTeam)
            }
            if !group.pharmacyJoinCode.isEmpty, group.pharmacyJoinCode.lowercased() == normalized {
                return GroupJoinResult(group: group, accountKind: .pharmacy)
            }
        }
        return nil
    }

    @discardableResult
    func createUser(name: String, abbreviation: String, groupID: UUID) async throws -> User {
        let user = User(name: name, abbreviation: abbreviation, role: .member, groupID: groupID)
        context.insert(user)
        try context.save()
        return user
    }

    @discardableResult
    func createPharmacyUser(firmName: String, groupID: UUID) async throws -> User {
        let user = User(name: firmName, abbreviation: "", role: .member, accountKind: .pharmacy, groupID: groupID)
        context.insert(user)
        try context.save()
        return user
    }

    func updateUser(id: UUID, name: String, abbreviation: String) async throws {
        guard let user = try await user(id: id) else { return }
        user.name = name
        user.abbreviation = abbreviation
        try context.save()
    }

    func setRole(id: UUID, role: UserRole, bypassLastAdminGuard: Bool = false) async throws {
        guard let user = try await user(id: id) else { return }
        if !bypassLastAdminGuard, user.role == .admin, role != .admin, let groupID = user.groupID {
            let adminCount = try await allUsers(inGroup: groupID).filter { $0.role == .admin }.count
            guard adminCount > 1 else { throw UserRepositoryError.cannotRemoveLastAdmin }
        }
        user.role = role
        try context.save()
    }

    func deleteUser(id: UUID, bypassLastAdminGuard: Bool = false) async throws {
        guard let user = try await user(id: id) else { return }
        if !bypassLastAdminGuard, let groupID = user.groupID {
            let adminCount = try await allUsers(inGroup: groupID).filter { $0.role == .admin }.count
            guard canRemoveUser(user, adminCountInGroup: adminCount) else {
                throw UserRepositoryError.cannotRemoveLastAdmin
            }
        }
        context.delete(user)
        try context.save()
    }
}
