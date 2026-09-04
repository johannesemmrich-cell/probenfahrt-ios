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

    /// Call when a conversation is opened — its unread messages no longer
    /// count, so call `refresh` afterwards to update the badges.
    func markRead(conversationKey: String) {
        lastReadByConversation[conversationKey] = .now
    }

    @MainActor
    func refresh(currentUser: User, chatRepository: ChatRepository = CloudKitChatRepository()) async {
        guard let groupID = currentUser.groupID else {
            unreadCount = 0
            return
        }
        do {
            var total = 0

            let groupMessages = try await chatRepository.groupMessages(groupID: groupID)
            let groupLastRead = lastRead(conversationKey: Self.groupConversationKey)
            total += groupMessages.filter { $0.senderID != currentUser.id && $0.createdAt > groupLastRead }.count

            let partnerIDs = try await chatRepository.conversationPartnerIDs(groupID: groupID, currentUserID: currentUser.id)
            for partnerID in partnerIDs {
                let messages = try await chatRepository.directMessages(groupID: groupID, between: currentUser.id, and: partnerID)
                let partnerLastRead = lastRead(conversationKey: partnerID.uuidString)
                total += messages.filter { $0.senderID == partnerID && $0.createdAt > partnerLastRead }.count
            }

            unreadCount = total
            try? await UNUserNotificationCenter.current().setBadgeCount(total)
        } catch {
            // Transient failure — badges just stay at their last known value.
        }
    }
}
