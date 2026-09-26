import Foundation

struct SurveyDayRow: Identifiable {
    let day: SurveyDay
    let entries: [SurveyEntry]
    var id: UUID { day.id }

    /// Row-background emphasis for the Umfragen list. `.conflict` covers two
    /// distinct problems that both need admin attention: a locked day that
    /// still has a sign-up, and an unlocked day with more than one sign-up —
    /// only one person can actually drive, so 2+ sign-ups is a clash, not a
    /// confirmed plan, and must not read as the same "all good" green as
    /// exactly one sign-up.
    enum Highlight {
        case none, confirmed, conflict
    }

    var highlight: Highlight {
        if (day.isLocked && !entries.isEmpty) || entries.count > 1 {
            return .conflict
        }
        if entries.count == 1 {
            return .confirmed
        }
        return .none
    }
}
