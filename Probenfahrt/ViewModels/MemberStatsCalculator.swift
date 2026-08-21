import Foundation

/// Pure trip-count aggregation for the admin "Mitglieder verwalten" member
/// detail screen — lifetime total plus a count scoped to an arbitrary
/// DateInterval (a week or a month), so the view can drive it with a simple
/// period toggle + prev/next navigation.
enum MemberStatsCalculator {
    static func totalTrips(for userID: UUID, entries: [SurveyEntryWithDate]) -> Int {
        entries.filter { $0.entry.userID == userID }.count
    }

    static func tripCount(for userID: UUID, entries: [SurveyEntryWithDate], in interval: DateInterval) -> Int {
        entries.filter { entryWithDate in
            entryWithDate.entry.userID == userID && interval.contains(entryWithDate.date)
        }.count
    }
}
