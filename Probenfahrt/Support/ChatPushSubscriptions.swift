import CloudKit
import Foundation

/// Registers the two CloudKit query subscriptions (group messages, direct
/// messages to me) that make Team-Chat push notifications work. Saving a
/// `CKSubscription` with a deterministic ID that already exists just updates
/// it in place, so `ensure` is safe to call on every launch — no separate
/// "did we already subscribe" bookkeeping needed.
///
/// Requires the "Push Notifications" + "Background Modes → Remote
/// notifications" capabilities on the App ID (see README.md "CloudKit-
/// Setup") — with Automatic Signing this is normally provisioned the same
/// way the iCloud container itself is, the first time the app runs with a
/// selected team.
enum ChatPushSubscriptions {
    private enum RecordType {
        static let message = "ChatMessage"
    }

    private enum Field {
        static let groupID = "groupID"
        static let senderID = "senderID"
        static let recipientID = "recipientID"
    }

    private static let groupSentinel = "group"

    static func ensure(groupID: UUID, currentUserID: UUID) async {
        let database = CKContainer(identifier: CloudKitConfig.containerIdentifier).publicCloudDatabase

        let groupPredicate = NSPredicate(
            format: "%K == %@ AND %K == %@ AND %K != %@",
            Field.groupID, groupID.uuidString,
            Field.recipientID, groupSentinel,
            Field.senderID, currentUserID.uuidString
        )
        let groupSubscription = CKQuerySubscription(
            recordType: RecordType.message,
            predicate: groupPredicate,
            subscriptionID: "chat-group-\(groupID.uuidString)-\(currentUserID.uuidString)",
            options: [.firesOnRecordCreation]
        )
        groupSubscription.notificationInfo = notificationInfo(alertBody: "Neue Nachricht im Team-Chat")

        let dmPredicate = NSPredicate(
            format: "%K == %@ AND %K == %@",
            Field.groupID, groupID.uuidString,
            Field.recipientID, currentUserID.uuidString
        )
        let dmSubscription = CKQuerySubscription(
            recordType: RecordType.message,
            predicate: dmPredicate,
            subscriptionID: "chat-dm-\(groupID.uuidString)-\(currentUserID.uuidString)",
            options: [.firesOnRecordCreation]
        )
        dmSubscription.notificationInfo = notificationInfo(alertBody: "Neue Direktnachricht")

        // Best-effort: if the schema isn't marked Queryable yet, or the
        // device has no push capability, chat itself still works fine
        // without live notifications.
        _ = try? await database.save(groupSubscription)
        _ = try? await database.save(dmSubscription)
    }

    private static func notificationInfo(alertBody: String) -> CKSubscription.NotificationInfo {
        let info = CKSubscription.NotificationInfo()
        info.alertBody = alertBody
        info.shouldSendContentAvailable = true
        info.shouldBadge = false // badge count is computed client-side, see UnreadMessagesStore
        info.soundName = "default"
        return info
    }
}
