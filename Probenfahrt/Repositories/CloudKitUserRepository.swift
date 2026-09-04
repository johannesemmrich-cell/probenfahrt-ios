import CloudKit
import Foundation

/// CloudKit-backed implementation of UserRepository (BACKLOG #1), replacing
/// the local SwiftData mock so Mitglieder/Gruppen-Beitritt real, shared team
/// data reflect — analog to CloudKitSamplesRepository for the Proben-Bereich.
/// Same public database, same container, same paging/error-handling helper
/// (CloudKitQuerying).
///
/// Requires the CloudKit Dashboard schema for both record types to mark
/// `joinCode`/`pharmacyJoinCode` (TeamGroup) and `groupID` (User) as
/// Queryable — see the CloudKit setup checklist in README.md.
@MainActor
final class CloudKitUserRepository: UserRepository {
    private let database: CKDatabase

    init(container: CKContainer = CKContainer(identifier: CloudKitConfig.containerIdentifier)) {
        self.database = container.publicCloudDatabase
    }

    private enum RecordType {
        static let group = "TeamGroup"
        static let user = "User"
    }

    private enum GroupField {
        static let groupID = "groupID"
        static let name = "name"
        static let joinCode = "joinCode"
        static let pharmacyJoinCode = "pharmacyJoinCode"
        static let createdAt = "createdAt"
    }

    private enum UserField {
        static let userID = "userID"
        static let name = "name"
        static let abbreviation = "abbreviation"
        static let role = "role"
        static let accountKind = "accountKind"
        static let groupID = "groupID"
        static let createdAt = "createdAt"
    }

    // MARK: - Group seeding (not part of UserRepository — only MockDataSeeder
    // ever creates a group; there's no in-app "create group" flow)

    /// Idempotent find-or-create keyed by the lowercased `joinCode` — safe to
    /// call on every launch without ever creating a duplicate group. Codes
    /// are stored lowercased (see `resolveJoinCode`, which queries with a
    /// plain `==` — CloudKit's query engine doesn't reliably support the
    /// `[c]` case-insensitive predicate modifier, so case-insensitivity has
    /// to happen by normalizing both sides instead of at query time).
    func ensureGroupExists(name: String, joinCode: String, pharmacyJoinCode: String) async throws -> TeamGroup {
        let normalizedJoinCode = joinCode.lowercased()
        let normalizedPharmacyJoinCode = pharmacyJoinCode.lowercased()
        let recordID = Self.groupRecordID(joinCode: normalizedJoinCode)

        if let existing = try? await database.record(for: recordID) {
            let current = Self.group(from: existing)
            // Self-heals records created before codes were normalized to
            // lowercase — keeps the existing id (Users already reference
            // it) but refreshes the code fields so resolveJoinCode's
            // exact-match query keeps finding them.
            guard current.joinCode != normalizedJoinCode || current.pharmacyJoinCode != normalizedPharmacyJoinCode else {
                return current
            }
            let healed = TeamGroup(id: current.id, name: current.name, joinCode: normalizedJoinCode, pharmacyJoinCode: normalizedPharmacyJoinCode, createdAt: current.createdAt)
            Self.apply(healed, to: existing)
            let saved = try await database.save(existing)
            return Self.group(from: saved)
        }

        let group = TeamGroup(name: name, joinCode: normalizedJoinCode, pharmacyJoinCode: normalizedPharmacyJoinCode)
        let record = CKRecord(recordType: RecordType.group, recordID: recordID)
        Self.apply(group, to: record)
        let saved = try await database.save(record)
        return Self.group(from: saved)
    }

    // MARK: - UserRepository

    func allUsers(inGroup groupID: UUID) async throws -> [User] {
        let predicate = NSPredicate(format: "%K == %@", UserField.groupID, groupID.uuidString)
        let query = CKQuery(recordType: RecordType.user, predicate: predicate)
        return try await allRecords(matching: query)
            .map(Self.user(from:))
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func user(id: UUID) async throws -> User? {
        guard let record = try? await database.record(for: Self.userRecordID(id: id)) else { return nil }
        return Self.user(from: record)
    }

    func isAbbreviationTaken(_ abbreviation: String, inGroup groupID: UUID) async throws -> Bool {
        let normalized = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let users = try await allUsers(inGroup: groupID)
        return users.contains { $0.abbreviation.lowercased() == normalized }
    }

    func resolveJoinCode(_ code: String) async throws -> GroupJoinResult? {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        let joinCodePredicate = NSPredicate(format: "%K == %@", GroupField.joinCode, normalized)
        if let record = try await allRecords(matching: CKQuery(recordType: RecordType.group, predicate: joinCodePredicate)).first {
            return GroupJoinResult(group: Self.group(from: record), accountKind: .labTeam)
        }

        let pharmacyPredicate = NSPredicate(format: "%K == %@", GroupField.pharmacyJoinCode, normalized)
        if let record = try await allRecords(matching: CKQuery(recordType: RecordType.group, predicate: pharmacyPredicate)).first {
            return GroupJoinResult(group: Self.group(from: record), accountKind: .pharmacy)
        }

        return nil
    }

    @discardableResult
    func createUser(name: String, abbreviation: String, groupID: UUID) async throws -> User {
        try await save(User(name: name, abbreviation: abbreviation, role: .member, groupID: groupID))
    }

    /// Only used by MockDataSeeder — real onboarding always creates
    /// `.member` users via `createUser`; the demo fixtures need one seeded
    /// as `.admin` so the Debug/UI-test group has someone to manage it.
    @discardableResult
    func createSeedUser(name: String, abbreviation: String, role: UserRole, groupID: UUID) async throws -> User {
        try await save(User(name: name, abbreviation: abbreviation, role: role, groupID: groupID))
    }

    @discardableResult
    func createPharmacyUser(firmName: String, groupID: UUID) async throws -> User {
        try await save(User(name: firmName, abbreviation: "", role: .member, accountKind: .pharmacy, groupID: groupID))
    }

    func updateUser(id: UUID, name: String, abbreviation: String) async throws {
        guard let record = try? await database.record(for: Self.userRecordID(id: id)) else { return }
        record[UserField.name] = name as CKRecordValue
        record[UserField.abbreviation] = abbreviation as CKRecordValue
        _ = try await database.save(record)
    }

    func setRole(id: UUID, role: UserRole, bypassLastAdminGuard: Bool = false) async throws {
        guard let record = try? await database.record(for: Self.userRecordID(id: id)) else { return }
        let user = Self.user(from: record)
        if !bypassLastAdminGuard, user.role == .admin, role != .admin, let groupID = user.groupID {
            let adminCount = try await allUsers(inGroup: groupID).filter { $0.role == .admin }.count
            guard adminCount > 1 else { throw UserRepositoryError.cannotRemoveLastAdmin }
        }
        record[UserField.role] = role.rawValue as CKRecordValue
        _ = try await database.save(record)
    }

    func deleteUser(id: UUID, bypassLastAdminGuard: Bool = false) async throws {
        guard let user = try await user(id: id) else { return }
        if !bypassLastAdminGuard, let groupID = user.groupID {
            let adminCount = try await allUsers(inGroup: groupID).filter { $0.role == .admin }.count
            guard canRemoveUser(user, adminCountInGroup: adminCount) else {
                throw UserRepositoryError.cannotRemoveLastAdmin
            }
        }
        try await database.deleteRecord(withID: Self.userRecordID(id: id))
    }

    // MARK: - Helpers

    private func allRecords(matching query: CKQuery) async throws -> [CKRecord] {
        try await CloudKitQuerying.allRecords(matching: query, in: database)
    }

    private func save(_ user: User) async throws -> User {
        let record = CKRecord(recordType: RecordType.user, recordID: Self.userRecordID(id: user.id))
        Self.apply(user, to: record)
        let saved = try await database.save(record)
        return Self.user(from: saved)
    }

    // MARK: - Record IDs

    private static func groupRecordID(joinCode: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "group-\(joinCode.lowercased())")
    }

    private static func userRecordID(id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "user-\(id.uuidString)")
    }

    // MARK: - CKRecord <-> model mapping

    private static func apply(_ group: TeamGroup, to record: CKRecord) {
        record[GroupField.groupID] = group.id.uuidString as CKRecordValue
        record[GroupField.name] = group.name as CKRecordValue
        record[GroupField.joinCode] = group.joinCode as CKRecordValue
        record[GroupField.pharmacyJoinCode] = group.pharmacyJoinCode as CKRecordValue
        record[GroupField.createdAt] = group.createdAt as CKRecordValue
    }

    private static func group(from record: CKRecord) -> TeamGroup {
        let id = (record[GroupField.groupID] as? String).flatMap(UUID.init) ?? UUID()
        return TeamGroup(
            id: id,
            name: (record[GroupField.name] as? String) ?? "",
            joinCode: (record[GroupField.joinCode] as? String) ?? "",
            pharmacyJoinCode: (record[GroupField.pharmacyJoinCode] as? String) ?? "",
            createdAt: (record[GroupField.createdAt] as? Date) ?? .now
        )
    }

    private static func apply(_ user: User, to record: CKRecord) {
        record[UserField.userID] = user.id.uuidString as CKRecordValue
        record[UserField.name] = user.name as CKRecordValue
        record[UserField.abbreviation] = user.abbreviation as CKRecordValue
        record[UserField.role] = user.role.rawValue as CKRecordValue
        record[UserField.accountKind] = user.accountKind.rawValue as CKRecordValue
        record[UserField.groupID] = user.groupID?.uuidString as CKRecordValue?
        record[UserField.createdAt] = user.createdAt as CKRecordValue
    }

    private static func user(from record: CKRecord) -> User {
        let id = (record[UserField.userID] as? String).flatMap(UUID.init) ?? UUID()
        let role = (record[UserField.role] as? String).flatMap(UserRole.init(rawValue:)) ?? .member
        let accountKind = (record[UserField.accountKind] as? String).flatMap(AccountKind.init(rawValue:)) ?? .labTeam
        let groupID = (record[UserField.groupID] as? String).flatMap(UUID.init)
        return User(
            id: id,
            name: (record[UserField.name] as? String) ?? "",
            abbreviation: (record[UserField.abbreviation] as? String) ?? "",
            role: role,
            accountKind: accountKind,
            groupID: groupID,
            createdAt: (record[UserField.createdAt] as? Date) ?? .now
        )
    }
}
