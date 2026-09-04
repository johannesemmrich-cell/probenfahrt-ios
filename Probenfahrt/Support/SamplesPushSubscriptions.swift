import CloudKit
import Foundation

/// Registers the CloudKit query subscription that pushes a notification to
/// every lab-team member as soon as any pharmacy/location reports samples —
/// same idea as ChatPushSubscriptions, but broadcast to the whole group
/// instead of a specific recipient, and matching on the record's *current*
/// state (`hasSamples == 1`) rather than just creation, since a location can
/// flip an existing same-day report from "Keine Proben" to "Ja" (see
/// SampleReport.swift) — creation-only would miss that.
///
/// Requires `groupID` and `hasSamples` marked Queryable on `SampleReport` in
/// the CloudKit Dashboard (see README.md "CloudKit-Setup") — `hasSamples`
/// wasn't needed there before this subscription.
enum SamplesPushSubscriptions {
    private enum RecordType {
        static let report = "SampleReport"
    }

    private enum Field {
        static let groupID = "groupID"
        static let hasSamples = "hasSamples"
    }

    static func ensure(groupID: UUID, currentUserID: UUID) async {
        let database = CKContainer(identifier: CloudKitConfig.containerIdentifier).publicCloudDatabase

        let predicate = NSPredicate(
            format: "%K == %@ AND %K == 1",
            Field.groupID, groupID.uuidString,
            Field.hasSamples
        )
        let subscription = CKQuerySubscription(
            recordType: RecordType.report,
            predicate: predicate,
            subscriptionID: "samples-\(groupID.uuidString)-\(currentUserID.uuidString)",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.alertBody = "Neue Probenmeldung"
        info.shouldSendContentAvailable = true
        info.shouldBadge = false
        info.soundName = "default"
        subscription.notificationInfo = info

        // Best-effort, same tradeoff as ChatPushSubscriptions: without the
        // right schema/push setup the Proben tab itself still works fine,
        // just without a live notification.
        _ = try? await database.save(subscription)
    }
}
