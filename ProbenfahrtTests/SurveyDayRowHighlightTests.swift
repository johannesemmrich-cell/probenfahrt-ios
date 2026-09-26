import Testing
import Foundation
@testable import Probenfahrt

struct SurveyDayRowHighlightTests {
    private func row(isLocked: Bool, entryCount: Int) -> SurveyDayRow {
        let day = SurveyDay(date: .now, groupID: nil, isLocked: isLocked)
        let entries = (0..<entryCount).map { _ in
            SurveyEntry(surveyDayID: day.id, userID: UUID())
        }
        return SurveyDayRow(day: day, entries: entries)
    }

    @Test func noEntriesUnlockedIsNone() {
        #expect(row(isLocked: false, entryCount: 0).highlight == .none)
    }

    @Test func noEntriesLockedIsNone() {
        #expect(row(isLocked: true, entryCount: 0).highlight == .none)
    }

    @Test func exactlyOneEntryUnlockedIsConfirmed() {
        #expect(row(isLocked: false, entryCount: 1).highlight == .confirmed)
    }

    /// The bug reported 2026-09-26: two people signing up for the same
    /// unlocked day is a scheduling clash (only one can actually drive), not
    /// a confirmed plan — it must not render as the same green as exactly
    /// one sign-up.
    @Test func twoOrMoreEntriesUnlockedIsConflict() {
        #expect(row(isLocked: false, entryCount: 2).highlight == .conflict)
        #expect(row(isLocked: false, entryCount: 3).highlight == .conflict)
    }

    @Test func lockedWithOneEntryIsConflict() {
        #expect(row(isLocked: true, entryCount: 1).highlight == .conflict)
    }

    @Test func lockedWithMultipleEntriesIsConflict() {
        #expect(row(isLocked: true, entryCount: 2).highlight == .conflict)
    }
}
