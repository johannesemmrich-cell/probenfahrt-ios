import Testing
import Foundation
@testable import Probenfahrt

struct MonthlyReportGeneratorTests {
    private static let calendar = Calendar.current
    private static let referenceNow = Date.now
    private static let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceNow)!

    @Test func aggregatesTripCountsPerUser() {
        let userA = User(name: "Anna Weber", abbreviation: "AW")
        let userB = User(name: "Bruno Klein", abbreviation: "BK")
        let dayID = UUID()

        let entries: [SurveyEntryWithDate] = [
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: dayID, userID: userA.id), date: Self.yesterday),
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: dayID, userID: userA.id), date: Self.yesterday),
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: dayID, userID: userB.id), date: Self.yesterday),
        ]

        let lines = MonthlyReportGenerator.generate(entries: entries, users: [userA, userB], asOf: Self.referenceNow)

        #expect(lines.count == 2)
        #expect(lines.first?.userName == "Anna Weber")
        #expect(lines.first?.tripCount == 2)
        #expect(lines.last?.userName == "Bruno Klein")
        #expect(lines.last?.tripCount == 1)
    }

    @Test func excludesEntriesForDaysNotYetOver() {
        let user = User(name: "Anna Weber", abbreviation: "AW")
        let dayID = UUID()

        let entries: [SurveyEntryWithDate] = [
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: dayID, userID: user.id), date: Self.yesterday),
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: dayID, userID: user.id), date: Self.calendar.startOfDay(for: Self.referenceNow)),
        ]

        let lines = MonthlyReportGenerator.generate(entries: entries, users: [user], asOf: Self.referenceNow)

        #expect(lines.count == 1)
        #expect(lines.first?.tripCount == 1)
    }

    @Test func emptyEntriesProduceEmptyReport() {
        let lines = MonthlyReportGenerator.generate(entries: [], users: [], asOf: Self.referenceNow)
        #expect(lines.isEmpty)
    }

    @Test func ignoresEntriesForUnknownUsers() {
        let entries = [SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: UUID()), date: Self.yesterday)]
        let lines = MonthlyReportGenerator.generate(entries: entries, users: [], asOf: Self.referenceNow)
        #expect(lines.isEmpty)
    }

    /// A removed member must still show up with their past trip count — as
    /// long as the caller passes `allUsersIncludingRemoved` (real callers
    /// do, see AdminReportView), a soft-deleted user still resolves here.
    @Test func includesRemovedUsersWhenPassedIn() {
        let removedUser = User(name: "Clara Fuchs", abbreviation: "CF", isRemoved: true)
        let entries: [SurveyEntryWithDate] = [
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: removedUser.id), date: Self.yesterday),
        ]

        let lines = MonthlyReportGenerator.generate(entries: entries, users: [removedUser], asOf: Self.referenceNow)

        #expect(lines.count == 1)
        #expect(lines.first?.userName == "Clara Fuchs")
        #expect(lines.first?.tripCount == 1)
    }
}
