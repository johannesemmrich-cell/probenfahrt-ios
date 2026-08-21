import Testing
import Foundation
@testable import Probenfahrt

struct MemberStatsCalculatorTests {
    @Test func totalTripsCountsOnlyMatchingUser() {
        let userA = UUID()
        let userB = UUID()
        let entries = [
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: userA), date: .now),
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: userA), date: .now),
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: userB), date: .now),
        ]
        #expect(MemberStatsCalculator.totalTrips(for: userA, entries: entries) == 2)
        #expect(MemberStatsCalculator.totalTrips(for: userB, entries: entries) == 1)
    }

    @Test func tripCountOnlyCountsEntriesInsideInterval() {
        let user = UUID()
        let calendar = Calendar.current
        let now = Date.now
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!

        let entries = [
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: user), date: now),
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: user), date: lastMonth),
        ]
        let thisMonthInterval = calendar.dateInterval(of: .month, for: now)!
        #expect(MemberStatsCalculator.tripCount(for: user, entries: entries, in: thisMonthInterval) == 1)
    }

    @Test func tripCountIgnoresOtherUsers() {
        let userA = UUID()
        let userB = UUID()
        let now = Date.now
        let entries = [
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: userA), date: now),
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: userB), date: now),
        ]
        let interval = Calendar.current.dateInterval(of: .weekOfYear, for: now)!
        #expect(MemberStatsCalculator.tripCount(for: userA, entries: entries, in: interval) == 1)
    }
}
