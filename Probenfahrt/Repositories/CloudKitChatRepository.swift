import CloudKit
import Foundation

/// CloudKit-backed implementation of ChatRepository (BACKLOG #1), replacing
/// the local SwiftData mock so Team-Chat real, shared team data reflect —
/// analog to CloudKitSamplesRepository for the Proben-Bereich.
///
/// `recipientID` is stored as a non-null string with a `"group"` sentinel
/// for group-channel messages (instead of leaving the field nil/absent for
/// them) so every query stays a simple equality check — no dependency on
/// CloudKit's nil/not-equal query support. Direct-message lookups run as two
/// simple equality queries merged client-side rather than a single OR
/// predicate, matching the rest of this codebase's CloudKit queries (all
/// plain ANDs).
///
/// Requires the CloudKit Dashboard schema to mark `groupID`/`senderID`/
/// `recipientID` as Queryable — see the CloudKit setup checklist in README.md.
@MainActor
final class CloudKitChatRepository: ChatRepository {
    private let database: CKDatabase

    init(container: CKContainer = CKContainer(identifier: CloudKitConfig.containerIdentifier)) {
        self.database = container.publicCloudDatabase
    }

    private enum RecordType {
        static let message = "ChatMessage"
    }

    private enum Field {
        static let messageID = "messageID"
        static let groupID = "groupID"
        static let senderID = "senderID"
        static let recipientID = "recipientID"
        static let text = "text"
        static let createdAt = "createdAt"
    }

    private static let groupSentinel = "group"

    // MARK: - ChatRepository

    func groupMessages(groupID: UUID) async throws -> [ChatMessage] {
        let predicate = NSPredicate(
            format: "%K == %@ AND %K == %@",
            Field.groupID, groupID.uuidString,
            Field.recipientID, Self.groupSentinel
        )
        let query = CKQuery(recordType: RecordType.message, predicate: predicate)
        return try await allRecords(matching: query).map(Self.message(from:)).sorted { $0.createdAt < $1.createdAt }
    }

    func directMessages(groupID: UUID, between userA: UUID, and userB: UUID) async throws -> [ChatMessage] {
        let aToB = try await messages(groupID: groupID, senderID: userA, recipientID: userB)
        let bToA = try await messages(groupID: groupID, senderID: userB, recipientID: userA)
        return (aToB + bToA).sorted { $0.createdAt < $1.createdAt }
    }

    func conversationPartnerIDs(groupID: UUID, currentUserID: UUID) async throws -> [UUID] {
        let sent = try await messages(groupID: groupID, senderID: currentUserID)
        let received = try await messages(groupID: groupID, recipientID: currentUserID)

        var partners = Set<UUID>()
        for message in sent {
            if let recipientID = message.recipientID { partners.insert(recipientID) }
        }
        for message in received {
            if let senderID = message.senderID { partners.insert(senderID) }
        }
        return Array(partners)
    }

    func sendGroupMessage(groupID: UUID, senderID: UUID, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await save(ChatMessage(groupID: groupID, senderID: senderID, text: trimmed))
    }

    func sendDirectMessage(groupID: UUID, senderID: UUID, recipientID: UUID, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await save(ChatMessage(groupID: groupID, senderID: senderID, recipientID: recipientID, text: trimmed))
    }

    /// Only used by MockDataSeeder to backdate demo chat history so it looks
    /// spread over several hours — real sends always use `Date.now` via
    /// `sendGroupMessage`/`sendDirectMessage`.
    func seedMessage(groupID: UUID, senderID: UUID, recipientID: UUID?, text: String, createdAt: Date) async throws {
        try await save(ChatMessage(groupID: groupID, senderID: senderID, recipientID: recipientID, text: text, createdAt: createdAt))
    }

    // MARK: - Helpers

    /// `recipientID` nil means "match only the sender" (used to find every
    /// message a user sent, group or DM); pass it to further scope to one
    /// specific DM direction.
    private func messages(groupID: UUID, senderID: UUID? = nil, recipientID: UUID? = nil) async throws -> [ChatMessage] {
        var format = "%K == %@"
        var args: [CVarArg] = [Field.groupID, groupID.uuidString]
        if let senderID {
            format += " AND %K == %@"
            args += [Field.senderID, senderID.uuidString]
        }
        if let recipientID {
            format += " AND %K == %@"
            args += [Field.recipientID, recipientID.uuidString]
        }
        let predicate = NSPredicate(format: format, argumentArray: args)
        let query = CKQuery(recordType: RecordType.message, predicate: predicate)
        return try await allRecords(matching: query).map(Self.message(from:))
    }

    private func save(_ message: ChatMessage) async throws {
        let record = CKRecord(recordType: RecordType.message, recordID: Self.messageRecordID(id: message.id))
        Self.apply(message, to: record)
        _ = try await database.save(record)
    }

    private func allRecords(matching query: CKQuery) async throws -> [CKRecord] {
        try await CloudKitQuerying.allRecords(matching: query, in: database)
    }

    // MARK: - Record IDs

    private static func messageRecordID(id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "message-\(id.uuidString)")
    }

    // MARK: - CKRecord <-> model mapping

    private static func apply(_ message: ChatMessage, to record: CKRecord) {
        record[Field.messageID] = message.id.uuidString as CKRecordValue
        record[Field.groupID] = message.groupID?.uuidString as CKRecordValue?
        record[Field.senderID] = message.senderID?.uuidString as CKRecordValue?
        record[Field.recipientID] = (message.recipientID?.uuidString ?? groupSentinel) as CKRecordValue
        record[Field.text] = message.text as CKRecordValue
        record[Field.createdAt] = message.createdAt as CKRecordValue
    }

    private static func message(from record: CKRecord) -> ChatMessage {
        let id = (record[Field.messageID] as? String).flatMap(UUID.init) ?? UUID()
        let groupID = (record[Field.groupID] as? String).flatMap(UUID.init)
        let senderID = (record[Field.senderID] as? String).flatMap(UUID.init)
        let recipientRaw = record[Field.recipientID] as? String
        let recipientID = (recipientRaw == groupSentinel) ? nil : recipientRaw.flatMap(UUID.init)
        return ChatMessage(
            id: id,
            groupID: groupID,
            senderID: senderID,
            recipientID: recipientID,
            text: (record[Field.text] as? String) ?? "",
            createdAt: (record[Field.createdAt] as? Date) ?? .now
        )
    }
}
