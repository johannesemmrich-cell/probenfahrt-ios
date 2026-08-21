import Testing
import Foundation
@testable import Probenfahrt

struct SurveyWeekWindowTests {
    private let calendar = Calendar.current

    @Test func alwaysReturnsExactlyTwoBlocks() {
        for offset in 0..<14 {
            let reference = calendar.date(byAdding: .day, value: offset, to: .now)!
            let blocks = SurveyWeekWindow.currentWeekBlocks(from: reference, calendar: calendar)
            #expect(blocks.count == 2)
        }
    }

    @Test func everyBlockHasFourMondayThroughThursdayDays() {
        for offset in 0..<14 {
            let reference = calendar.date(byAdding: .day, value: offset, to: .now)!
            let blocks = SurveyWeekWindow.currentWeekBlocks(from: reference, calendar: calendar)
            for block in blocks {
                #expect(block.days.count == 4)
                for date in block.days {
                    let weekday = calendar.component(.weekday, from: date)
                    #expect((2...5).contains(weekday))
                }
                #expect(block.days == block.days.sorted())
                #expect(block.weekStart == block.days.first)
                #expect(block.weekEnd == block.days.last)
            }
        }
    }

    @Test func secondBlockStartsExactlyOneWeekAfterFirst() {
        for offset in 0..<14 {
            let reference = calendar.date(byAdding: .day, value: offset, to: .now)!
            let blocks = SurveyWeekWindow.currentWeekBlocks(from: reference, calendar: calendar)
            let expectedGap = calendar.date(byAdding: .day, value: 7, to: blocks[0].weekStart)!
            #expect(blocks[1].weekStart == expectedGap)
        }
    }

    // MARK: — Freitags-Rollover

    @Test func mondayThroughThursdayAnchorsOnThisWeeksMonday() {
        for weekdayComponent in [2, 3, 4, 5] { // Mon...Thu
            var components = DateComponents()
            components.weekday = weekdayComponent
            let reference = calendar.nextDate(after: .now, matching: components, matchingPolicy: .nextTime)!
            let anchor = SurveyWeekWindow.currentAnchorMonday(from: reference, calendar: calendar)
            let expectedMonday = SurveyWeekWindow.mondayStartOfWeek(containing: reference, calendar: calendar)
            #expect(anchor == expectedMonday)
        }
    }

    @Test func fridaySaturdaySundayAnchorOnNextWeeksMonday() {
        for weekdayComponent in [6, 7, 1] { // Fri, Sat, Sun
            var components = DateComponents()
            components.weekday = weekdayComponent
            let reference = calendar.nextDate(after: .now, matching: components, matchingPolicy: .nextTime)!
            let anchor = SurveyWeekWindow.currentAnchorMonday(from: reference, calendar: calendar)
            let thisMonday = SurveyWeekWindow.mondayStartOfWeek(containing: reference, calendar: calendar)!
            let expectedNextMonday = calendar.date(byAdding: .day, value: 7, to: thisMonday)!
            #expect(anchor == expectedNextMonday)
        }
    }

    @Test func fridayBlocksSkipThatWeekEntirely() {
        var components = DateComponents()
        components.weekday = 6 // Friday
        let friday = calendar.nextDate(after: .now, matching: components, matchingPolicy: .nextTime)!
        let thisMonday = SurveyWeekWindow.mondayStartOfWeek(containing: friday, calendar: calendar)!

        let blocks = SurveyWeekWindow.currentWeekBlocks(from: friday, calendar: calendar)
        #expect(blocks[0].weekStart != thisMonday)
        #expect(blocks.allSatisfy { $0.weekStart > thisMonday })
    }

    @Test func firstBlockContainsReferenceDatesWeekOnMondayThroughThursday() {
        for weekdayComponent in [2, 3, 4, 5] {
            var components = DateComponents()
            components.weekday = weekdayComponent
            let reference = calendar.nextDate(after: .now, matching: components, matchingPolicy: .nextTime)!
            let blocks = SurveyWeekWindow.currentWeekBlocks(from: reference, calendar: calendar)
            let referenceMonday = SurveyWeekWindow.mondayStartOfWeek(containing: reference, calendar: calendar)!
            #expect(blocks[0].weekStart == referenceMonday)
        }
    }

    @Test func mondayReferenceIsItsOwnWeekStart() {
        var components = DateComponents()
        components.weekday = 2 // Monday
        let monday = calendar.nextDate(after: .now, matching: components, matchingPolicy: .nextTime)!
        let blocks = SurveyWeekWindow.currentWeekBlocks(from: monday, calendar: calendar)
        #expect(blocks[0].weekStart == calendar.startOfDay(for: monday))
    }

    // MARK: — pastWeekBlocks (PastSurveysView grouping)

    @Test func pastWeekBlocksReturnsExactlyWeeksBackBlocks() {
        for offset in 0..<14 {
            let reference = calendar.date(byAdding: .day, value: offset, to: .now)!
            let blocks = SurveyWeekWindow.pastWeekBlocks(from: reference, calendar: calendar, weeksBack: 8)
            #expect(blocks.count == 8)
        }
    }

    @Test func pastWeekBlocksAreEachValidMondayThroughThursdayWeeks() {
        for offset in 0..<14 {
            let reference = calendar.date(byAdding: .day, value: offset, to: .now)!
            let blocks = SurveyWeekWindow.pastWeekBlocks(from: reference, calendar: calendar)
            for block in blocks {
                #expect(block.days.count == 4)
                #expect(block.weekStart == block.days.first)
                #expect(block.weekEnd == block.days.last)
                for date in block.days {
                    #expect((2...5).contains(calendar.component(.weekday, from: date)))
                }
            }
        }
    }

    @Test func pastWeekBlocksAreOrderedMostRecentFirstWithNoGapBetweenConsecutiveWeeks() {
        for offset in 0..<14 {
            let reference = calendar.date(byAdding: .day, value: offset, to: .now)!
            let blocks = SurveyWeekWindow.pastWeekBlocks(from: reference, calendar: calendar)
            for i in 0..<(blocks.count - 1) {
                let expectedNext = calendar.date(byAdding: .day, value: -7, to: blocks[i].weekStart)!
                #expect(blocks[i + 1].weekStart == expectedNext)
            }
        }
    }

    @Test func pastWeekBlocksNeverOverlapOrGapAgainstCurrentWeekBlocks() {
        for offset in 0..<14 {
            let reference = calendar.date(byAdding: .day, value: offset, to: .now)!
            let pastBlocks = SurveyWeekWindow.pastWeekBlocks(from: reference, calendar: calendar)
            let currentBlocks = SurveyWeekWindow.currentWeekBlocks(from: reference, calendar: calendar)
            // The most recent past week is exactly the calendar week
            // immediately before the current anchor week — no skipped or
            // duplicated week in between (Fri–Sun aren't survey days, so a
            // gap there is expected and not what this checks).
            let expectedNewestPastWeekStart = calendar.date(byAdding: .day, value: -7, to: currentBlocks[0].weekStart)!
            #expect(pastBlocks[0].weekStart == expectedNewestPastWeekStart)
            for block in pastBlocks {
                #expect(block.weekEnd < currentBlocks[0].weekStart)
            }
        }
    }
}
