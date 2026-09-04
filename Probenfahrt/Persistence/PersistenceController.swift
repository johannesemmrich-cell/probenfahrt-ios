import Foundation
import SwiftData

enum PersistenceController {
    static var schema: Schema {
        Schema([
            User.self,
            TeamGroup.self,
            SurveyDay.self,
            SurveyEntry.self,
            ChatMessage.self,
            SampleLocation.self,
            SampleReport.self,
            FeedbackEntry.self,
            DevTodoItem.self,
        ])
    }

    /// Launch argument used by UI tests to guarantee a fresh, isolated store +
    /// cleared UserDefaults on every run — otherwise a 2nd test run would find
    /// onboarding already completed from the 1st run's persisted session.
    static let uiTestResetArgument = "-UITest_ResetState"

    /// Creates the on-device store and seeds mock data on first launch.
    /// A failed container init is unrecoverable at app start, so we crash
    /// loudly here rather than limping along without persistence.
    @MainActor
    static func makeContainer() -> ModelContainer {
        let isUITesting = ProcessInfo.processInfo.arguments.contains(uiTestResetArgument)
        if isUITesting, let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        // cloudKitDatabase: .none — without this, SwiftData sees the app's
        // iCloud/CloudKit entitlement (added for CloudKitSamplesRepository,
        // see Repositories/) and defaults to automatically mirroring *all*
        // local models (Chat, Users, Umfragen...) into the private CloudKit
        // database. That was never intended; only Proben goes through
        // CloudKit, and does so via its own CKContainer-based repository,
        // not SwiftData's sync.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }
}
