import Foundation
import SwiftData

@MainActor
protocol UserRepository {
    func allUsers(inGroup groupID: UUID) async throws -> [User]
    func user(id: UUID) async throws -> User?
    func isAbbreviationTaken(_ abbreviation: String, inGroup groupID: UUID) async throws -> Bool
    func resolveGroup(joinCode: String) async throws -> TeamGroup?
    @discardableResult
    func createUser(name: String, abbreviation: String, groupID: UUID) async throws -> User
    func updateUser(id: UUID, name: String, abbreviation: String) async throws
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

    func resolveGroup(joinCode: String) async throws -> TeamGroup? {
        let normalized = joinCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let groups = try context.fetch(FetchDescriptor<TeamGroup>())
        return groups.first { $0.joinCode.lowercased() == normalized }
    }

    @discardableResult
    func createUser(name: String, abbreviation: String, groupID: UUID) async throws -> User {
        let user = User(name: name, abbreviation: abbreviation, role: .member, groupID: groupID)
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
}
