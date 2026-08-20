import Testing
import Foundation
@testable import Probenfahrt

struct SurveyWeekWindowTests {
    private let calendar = Calendar.current

    @Test func alwaysReturnsMondayThroughThursday() {
        for offset in 0..<14 {
            let reference = calendar.date(byAdding: .day, value: offset, to: .now)!
            let dates = SurveyWeekWindow.upcomingDates(from: reference, calendar: calendar)
            for date in dates {
                let weekday = calendar.component(.weekday, from: date)
                #expect((2...5).contains(weekday))
            }
        }
    }

    @Test func alwaysReturnsExactlyEightDates() {
        // A 14-day inclusive window is exactly two full weeks, so it always
        // contains exactly two of each weekday — regardless of the start weekday.
        for offset in 0..<7 {
            let reference = calendar.date(byAdding: .day, value: offset, to: .now)!
            let dates = SurveyWeekWindow.upcomingDates(from: reference, calendar: calendar)
            #expect(dates.count == 8)
        }
    }

    @Test func isSortedAscendingAndWithinRange() {
        let reference = Date.now
        let dates = SurveyWeekWindow.upcomingDates(from: reference, calendar: calendar)
        let start = calendar.startOfDay(for: reference)
        let end = calendar.date(byAdding: .day, value: 13, to: start)!
        #expect(dates == dates.sorted())
        #expect(dates.allSatisfy { $0 >= start && $0 <= end })
    }

    @Test func mondayReferenceIncludesSameDayFirst() {
        var components = DateComponents()
        components.weekday = 2 // Monday
        let monday = calendar.nextDate(after: .now, matching: components, matchingPolicy: .nextTime)!
        let dates = SurveyWeekWindow.upcomingDates(from: monday, calendar: calendar)
        #expect(dates.first == calendar.startOfDay(for: monday))
    }
}
