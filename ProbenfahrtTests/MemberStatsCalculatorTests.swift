import Testing
import Foundation
@testable import Probenfahrt

struct MemberStatsCalculatorTests {
    private static let calendar = Calendar.current
    private static let referenceNow = Date.now
    private static let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceNow)!
    private static let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: referenceNow)!
    private static let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceNow)!

    @Test func totalTripsCountsOnlyMatchingUser() {
        let userA = UUID()
        let userB = UUID()
        let entries = [
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: userA), date: Self.yesterday),
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: userA), date: Self.twoDaysAgo),
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: userB), date: Self.yesterday),
        ]
        #expect(MemberStatsCalculator.totalTrips(for: userA, entries: entries, asOf: Self.referenceNow) == 2)
        #expect(MemberStatsCalculator.totalTrips(for: userB, entries: entries, asOf: Self.referenceNow) == 1)
    }

    @Test func totalTripsExcludesTodayAndFutureDays() {
        let user = UUID()
        let entries = [
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: user), date: Self.yesterday),
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: user), date: Self.calendar.startOfDay(for: Self.referenceNow)),
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: user), date: Self.tomorrow),
        ]
        #expect(MemberStatsCalculator.totalTrips(for: user, entries: entries, asOf: Self.referenceNow) == 1)
    }

    @Test func tripCountOnlyCountsEntriesInsideInterval() {
        let user = UUID()
        let lastMonth = Self.calendar.date(byAdding: .month, value: -1, to: Self.yesterday)!

        let entries = [
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: user), date: Self.yesterday),
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: user), date: lastMonth),
        ]
        let thisMonthInterval = Self.calendar.dateInterval(of: .month, for: Self.referenceNow)!
        #expect(MemberStatsCalculator.tripCount(for: user, entries: entries, in: thisMonthInterval, asOf: Self.referenceNow) == 1)
    }

    @Test func tripCountExcludesTodayEvenInsideInterval() {
        let user = UUID()
        let entries = [
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: user), date: Self.calendar.startOfDay(for: Self.referenceNow)),
        ]
        let thisWeekInterval = Self.calendar.dateInterval(of: .weekOfYear, for: Self.referenceNow)!
        #expect(MemberStatsCalculator.tripCount(for: user, entries: entries, in: thisWeekInterval, asOf: Self.referenceNow) == 0)
    }

    @Test func tripCountIgnoresOtherUsers() {
        let userA = UUID()
        let userB = UUID()
        let entries = [
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: userA), date: Self.yesterday),
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: userB), date: Self.yesterday),
        ]
        // A fixed window around `yesterday` rather than the real calendar's
        // current week - avoids flaking when "today" happens to be the
        // first weekday of the week (yesterday would then fall into the
        // previous weekOfYear interval).
        let interval = DateInterval(
            start: Self.calendar.date(byAdding: .day, value: -3, to: Self.yesterday)!,
            end: Self.calendar.date(byAdding: .day, value: 3, to: Self.yesterday)!
        )
        #expect(MemberStatsCalculator.tripCount(for: userA, entries: entries, in: interval, asOf: Self.referenceNow) == 1)
    }
}
