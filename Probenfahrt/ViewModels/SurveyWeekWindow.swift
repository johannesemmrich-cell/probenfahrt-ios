import Foundation

enum SurveyWeekWindow {
    /// One Mon–Thu calendar week shown as an "Umfragen-Block" in the Umfragen tab.
    struct WeekBlock: Identifiable, Equatable {
        let weekStart: Date // Monday, start of day
        let weekEnd: Date   // Thursday, start of day
        let days: [Date]    // Mon, Tue, Wed, Thu — start of day, ascending
        var id: Date { weekStart }
    }

    /// Always exactly 2 blocks: the "current" week (see `currentAnchorMonday`)
    /// and the following week — the "jede Woche ein Umfragen-Block, für zwei
    /// Wochen" spec. A week rolls off this list once it's no longer current
    /// (see SurveyRepository's Vergangene-Umfragen screen for anything older).
    static func currentWeekBlocks(from referenceDate: Date, calendar: Calendar = .current) -> [WeekBlock] {
        guard let anchor = currentAnchorMonday(from: referenceDate, calendar: calendar) else { return [] }
        return (0..<2).compactMap { weekOffset in
            guard let weekStart = calendar.date(byAdding: .day, value: weekOffset * 7, to: anchor) else { return nil }
            let days = (0..<4).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
            guard let weekEnd = days.last else { return nil }
            return WeekBlock(weekStart: weekStart, weekEnd: weekEnd, days: days)
        }
    }

    /// Monday of the "current" Umfragen week, given the Freitags-Rollover
    /// rule: Mon–Thu are the only survey days, so once Friday arrives that
    /// week is functionally over — the 2 "aktuell" blocks jump ahead to next
    /// week + the week after, and the just-finished week moves into
    /// Vergangene Umfragen. On Mon–Thu, "current" is still this calendar
    /// week, same as before.
    static func currentAnchorMonday(from referenceDate: Date, calendar: Calendar = .current) -> Date? {
        guard let thisMonday = mondayStartOfWeek(containing: referenceDate, calendar: calendar) else { return nil }
        let weekday = calendar.component(.weekday, from: calendar.startOfDay(for: referenceDate)) // 1=Sun...6=Fri...7=Sat
        let isPastThisWeeksSurveyDays = weekday == 1 || weekday >= 6 // Fri, Sat, Sun
        guard isPastThisWeeksSurveyDays else { return thisMonday }
        return calendar.date(byAdding: .day, value: 7, to: thisMonday)
    }

    /// Past Mon–Thu week blocks, most-recent-first, strictly before the
    /// current Umfragen anchor — same `WeekBlock` shape as
    /// `currentWeekBlocks`, so PastSurveysView can render vergangene
    /// Umfragen as the same kind of "Fahrplan"-grouped blocks. Never
    /// overlaps and never gaps with `currentWeekBlocks`' first block: the
    /// newest past block's `weekEnd` is always exactly one day before that
    /// block's `weekStart`.
    static func pastWeekBlocks(from referenceDate: Date, calendar: Calendar = .current, weeksBack: Int = 8) -> [WeekBlock] {
        guard let anchor = currentAnchorMonday(from: referenceDate, calendar: calendar) else { return [] }
        return (1...weeksBack).compactMap { weeksAgo -> WeekBlock? in
            guard let weekStart = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: anchor) else { return nil }
            let days = (0..<4).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
            guard let weekEnd = days.last else { return nil }
            return WeekBlock(weekStart: weekStart, weekEnd: weekEnd, days: days)
        }
    }

    /// Start of the Monday of the calendar week containing `date`.
    static func mondayStartOfWeek(containing date: Date, calendar: Calendar = .current) -> Date? {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay) // 1=Sun...2=Mon...7=Sat
        let daysSinceMonday = (weekday + 5) % 7 // Mon->0, Tue->1, ... Sun->6
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfDay)
    }
}
