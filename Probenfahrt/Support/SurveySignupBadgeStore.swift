import Foundation

/// Counts how many *other* team members have signed into an Umfragen day
/// since this device last opened the Umfragen tab — shown as a numeric
/// badge on the tab. In-app only (no push, unlike Chat/Proben): sign-ups are
/// lower-urgency, "see it next time you open the tab" information.
@Observable
final class SurveySignupBadgeStore {
    private(set) var count = 0

    private var lastChecked: Date {
        didSet { UserDefaults.standard.set(lastChecked.timeIntervalSince1970, forKey: storageKey) }
    }
    private let storageKey = "com.johannesemmrich.probenfahrt.surveysLastChecked"

    init() {
        let raw = UserDefaults.standard.double(forKey: storageKey)
        lastChecked = raw > 0 ? Date(timeIntervalSince1970: raw) : .distantPast
    }

    /// Call when the Umfragen tab is opened — clears the badge immediately;
    /// no network round trip needed since "checked" is just a timestamp.
    func markChecked() {
        lastChecked = .now
        count = 0
    }

    @MainActor
    func refresh(currentUser: User, surveyRepository: SurveyRepository = CloudKitSurveyRepository()) async {
        guard let groupID = currentUser.groupID else {
            count = 0
            return
        }
        do {
            let blocks = SurveyWeekWindow.currentWeekBlocks(from: .now)
            guard let start = blocks.first?.weekStart, let end = blocks.last?.weekEnd else {
                count = 0
                return
            }
            let days = try await surveyRepository.existingSurveyDays(from: start, to: end, groupID: groupID)
            let entries = try await surveyRepository.entries(forDayIDs: days.map(\.id))
            count = entries.filter { $0.userID != currentUser.id && $0.createdAt > lastChecked }.count
        } catch {
            // Transient failure — badge just stays at its last known value.
        }
    }
}
