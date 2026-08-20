import Testing
import Foundation
@testable import Probenfahrt

struct MonthlyReportGeneratorTests {
    @Test func aggregatesTripCountsPerUser() {
        let userA = User(name: "Anna Weber", abbreviation: "AW")
        let userB = User(name: "Bruno Klein", abbreviation: "BK")
        let dayID = UUID()

        let entries: [SurveyEntryWithDate] = [
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: dayID, userID: userA.id), date: .now),
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: dayID, userID: userA.id), date: .now),
            SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: dayID, userID: userB.id), date: .now),
        ]

        let lines = MonthlyReportGenerator.generate(entries: entries, users: [userA, userB])

        #expect(lines.count == 2)
        #expect(lines.first?.userName == "Anna Weber")
        #expect(lines.first?.tripCount == 2)
        #expect(lines.last?.userName == "Bruno Klein")
        #expect(lines.last?.tripCount == 1)
    }

    @Test func emptyEntriesProduceEmptyReport() {
        let lines = MonthlyReportGenerator.generate(entries: [], users: [])
        #expect(lines.isEmpty)
    }

    @Test func ignoresEntriesForUnknownUsers() {
        let entries = [SurveyEntryWithDate(entry: SurveyEntry(surveyDayID: UUID(), userID: UUID()), date: .now)]
        let lines = MonthlyReportGenerator.generate(entries: entries, users: [])
        #expect(lines.isEmpty)
    }
}
