import Foundation

enum SurveyWeekWindow {
    /// All Mon–Thu dates (start-of-day), from `referenceDate` through 13 days later —
    /// the "rollierend die nächsten 2 Wochen" window from the Umfragen tab spec.
    static func upcomingDates(from referenceDate: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: referenceDate)
        guard let end = calendar.date(byAdding: .day, value: 13, to: start) else { return [] }
        var dates: [Date] = []
        var cursor = start
        while cursor <= end {
            let weekday = calendar.component(.weekday, from: cursor) // 1=Sun...2=Mon...5=Thu...7=Sat
            if (2...5).contains(weekday) {
                dates.append(cursor)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return dates
    }
}
