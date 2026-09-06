import Foundation
import UserNotifications

/// Derives the Chat unread badge (tab badge + app icon badge) from per-
/// conversation "last read" timestamps kept only on this device — unread
/// state isn't itself synced via CloudKit, only the messages are. Refreshed
/// on launch, on foreground, and when a silent push wakes the app (see
/// AppDelegate), and whenever a conversation is opened (see ConversationView).
@Observable
final class UnreadMessagesStore {
    static let groupConversationKey = "group"

    private(set) var unreadCount = 0
    /// Keyed the same as `lastReadByConversation` (`groupConversationKey` or
    /// a DM partner's `UUID.uuidString`) — lets ChatView show which specific
    /// conversation has new messages, not just the total.
    private(set) var unreadCountsByConversation: [String: Int] = [:]

    private var lastReadByConversation: [String: Date] {
        didSet {
            let raw = lastReadByConversation.mapValues { $0.timeIntervalSince1970 }
            UserDefaults.standard.set(raw, forKey: storageKey)
        }
    }
    private let storageKey = "com.johannesemmrich.probenfahrt.lastReadByConversation"

    init() {
        let raw = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double] ?? [:]
        lastReadByConversation = raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    func lastRead(conversationKey: String) -> Date {
        lastReadByConversation[conversationKey] ?? .distantPast
    }

    func unreadCount(forConversation key: String) -> Int {
        unreadCountsByConversation[key] ?? 0
    }

    /// Call when a conversation is opened — its unread messages no longer
    /// count, so call `refresh` afterwards to update the badges.
    func markRead(conversationKey: String) {
        lastReadByConversation[conversationKey] = .now
    }

    @MainActor
    func refresh(currentUser: User, chatRepository: ChatRepository = CloudKitChatRepository()) async {
        guard let groupID = currentUser.groupID else {
            unreadCount = 0
            unreadCountsByConversation = [:]
            return
        }
        // Each conversation's count is fetched independently and starts from
        // the previous known value: one conversation's query failing (e.g. a
        // transient CloudKit error) must not wipe out already-good counts
        // for every other conversation, group included.
        var countsByConversation = unreadCountsByConversation

        if let groupMessages = try? await chatRepository.groupMessages(groupID: groupID) {
            let groupLastRead = lastRead(conversationKey: Self.groupConversationKey)
            countsByConversation[Self.groupConversationKey] =
                groupMessages.filter { $0.senderID != currentUser.id && $0.createdAt > groupLastRead }.count
        }

        if let partnerIDs = try? await chatRepository.conversationPartnerIDs(groupID: groupID, currentUserID: currentUser.id) {
            for partnerID in partnerIDs {
                guard let messages = try? await chatRepository.directMessages(groupID: groupID, between: currentUser.id, and: partnerID) else {
                    continue
                }
                let partnerLastRead = lastRead(conversationKey: partnerID.uuidString)
                countsByConversation[partnerID.uuidString] =
                    messages.filter { $0.senderID == partnerID && $0.createdAt > partnerLastRead }.count
            }
        }

        unreadCountsByConversation = countsByConversation
        unreadCount = countsByConversation.values.reduce(0, +)
        try? await UNUserNotificationCenter.current().setBadgeCount(unreadCount)
    }
}
