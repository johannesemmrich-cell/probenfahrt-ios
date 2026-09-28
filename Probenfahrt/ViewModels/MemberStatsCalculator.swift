import Foundation

/// Pure trip-count aggregation for the admin "Mitglieder verwalten" member
/// detail screen — lifetime total plus a count scoped to an arbitrary
/// DateInterval (a week or a month), so the view can drive it with a simple
/// period toggle + prev/next navigation.
///
/// A signed-up day only counts once it's over: signing up is a plan, not yet
/// a completed Fahrt, so entries for today or a future day are excluded
/// until midnight passes. `entryWithDate.date` is always the SurveyDay's
/// normalized start-of-day, so `date < startOfToday` is exactly "that day
/// has fully elapsed".
enum MemberStatsCalculator {
    static func totalTrips(for userID: UUID, entries: [SurveyEntryWithDate], asOf: Date, calendar: Calendar = .current) -> Int {
        let cutoff = calendar.startOfDay(for: asOf)
        return entries.filter { $0.entry.userID == userID && $0.date < cutoff }.count
    }

    static func tripCount(for userID: UUID, entries: [SurveyEntryWithDate], in interval: DateInterval, asOf: Date, calendar: Calendar = .current) -> Int {
        let cutoff = calendar.startOfDay(for: asOf)
        return entries.filter { entryWithDate in
            entryWithDate.entry.userID == userID && interval.contains(entryWithDate.date) && entryWithDate.date < cutoff
        }.count
    }
}
