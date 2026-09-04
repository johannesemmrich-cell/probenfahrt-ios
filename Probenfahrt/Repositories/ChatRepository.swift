import Foundation

@MainActor
protocol ChatRepository {
    func groupMessages(groupID: UUID) async throws -> [ChatMessage]
    func directMessages(groupID: UUID, between userA: UUID, and userB: UUID) async throws -> [ChatMessage]
    /// Distinct user ids the given user has an existing DM thread with.
    func conversationPartnerIDs(groupID: UUID, currentUserID: UUID) async throws -> [UUID]
    func sendGroupMessage(groupID: UUID, senderID: UUID, text: String) async throws
    func sendDirectMessage(groupID: UUID, senderID: UUID, recipientID: UUID, text: String) async throws
}
