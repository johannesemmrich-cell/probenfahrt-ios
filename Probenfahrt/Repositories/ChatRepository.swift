import Foundation
import SwiftData

@MainActor
protocol ChatRepository {
    func groupMessages(groupID: UUID) async throws -> [ChatMessage]
    func directMessages(groupID: UUID, between userA: UUID, and userB: UUID) async throws -> [ChatMessage]
    /// Distinct user ids the given user has an existing DM thread with.
    func conversationPartnerIDs(groupID: UUID, currentUserID: UUID) async throws -> [UUID]
    func sendGroupMessage(groupID: UUID, senderID: UUID, text: String) async throws
    func sendDirectMessage(groupID: UUID, senderID: UUID, recipientID: UUID, text: String) async throws
}

@MainActor
final class SwiftDataChatRepository: ChatRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func groupMessages(groupID: UUID) async throws -> [ChatMessage] {
        try context.fetch(FetchDescriptor<ChatMessage>(predicate: #Predicate<ChatMessage> {
            $0.groupID == groupID && $0.recipientID == nil
        }))
        .sorted { $0.createdAt < $1.createdAt }
    }

    func directMessages(groupID: UUID, between userA: UUID, and userB: UUID) async throws -> [ChatMessage] {
        try context.fetch(FetchDescriptor<ChatMessage>(predicate: #Predicate<ChatMessage> {
            $0.groupID == groupID &&
            (($0.senderID == userA && $0.recipientID == userB) ||
             ($0.senderID == userB && $0.recipientID == userA))
        }))
        .sorted { $0.createdAt < $1.createdAt }
    }

    func conversationPartnerIDs(groupID: UUID, currentUserID: UUID) async throws -> [UUID] {
        let messages = try context.fetch(FetchDescriptor<ChatMessage>(predicate: #Predicate<ChatMessage> {
            $0.groupID == groupID && $0.recipientID != nil &&
            ($0.senderID == currentUserID || $0.recipientID == currentUserID)
        }))
        var partners = Set<UUID>()
        for message in messages {
            if message.senderID == currentUserID, let recipient = message.recipientID {
                partners.insert(recipient)
            } else if message.recipientID == currentUserID, let sender = message.senderID {
                partners.insert(sender)
            }
        }
        return Array(partners)
    }

    func sendGroupMessage(groupID: UUID, senderID: UUID, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        context.insert(ChatMessage(groupID: groupID, senderID: senderID, text: trimmed))
        try context.save()
    }

    func sendDirectMessage(groupID: UUID, senderID: UUID, recipientID: UUID, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        context.insert(ChatMessage(groupID: groupID, senderID: senderID, recipientID: recipientID, text: trimmed))
        try context.save()
    }
}
