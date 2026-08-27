import Foundation

/// Mon–Sun week blocks for the "Vergangene Proben" screen — same grouping
/// idea as SurveyWeekWindow, but a full 7-day week since samples can be
/// reported any day (unlike survey days, which only ever run Mon–Thu).
enum SampleWeekWindow {
    struct WeekBlock: Identifiable, Equatable {
        let weekStart: Date // Monday, start of day
        let weekEnd: Date   // Sunday, start of day
        let days: [Date]    // Mon...Sun, start of day, ascending
        var id: Date { weekStart }
    }

    /// Most-recent-first week blocks, starting with the week containing
    /// `referenceDate` (so today's reports are always reachable through
    /// their week, not just via the separate "today" Proben tab) and going
    /// back `weeksBack` further weeks.
    static func pastWeekBlocks(from referenceDate: Date, calendar: Calendar = .current, weeksBack: Int = 8) -> [WeekBlock] {
        guard let thisMonday = SurveyWeekWindow.mondayStartOfWeek(containing: referenceDate, calendar: calendar) else { return [] }
        return (0..<weeksBack).compactMap { weeksAgo -> WeekBlock? in
            guard let weekStart = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: thisMonday) else { return nil }
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
            guard let weekEnd = days.last else { return nil }
            return WeekBlock(weekStart: weekStart, weekEnd: weekEnd, days: days)
        }
    }
}
