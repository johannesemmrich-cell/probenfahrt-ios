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
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        MockDataSeeder.seedIfNeeded(context: container.mainContext)
        return container
    }
}
