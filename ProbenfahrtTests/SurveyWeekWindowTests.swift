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

    // MARK: — pastRange (PastSurveysView boundary)

    @Test func pastRangeEndsExactlyOneDayBeforeCurrentBlocksStart() {
        for offset in 0..<14 {
            let reference = calendar.date(byAdding: .day, value: offset, to: .now)!
            let range = SurveyWeekWindow.pastRange(from: reference, calendar: calendar)!
            let blocks = SurveyWeekWindow.currentWeekBlocks(from: reference, calendar: calendar)
            let expectedEnd = calendar.date(byAdding: .day, value: -1, to: blocks[0].weekStart)!
            #expect(range.end == expectedEnd)
            #expect(range.start < range.end)
        }
    }

    @Test func pastRangeSpansExactlyTheRequestedLookbackDays() {
        for offset in 0..<14 {
            let reference = calendar.date(byAdding: .day, value: offset, to: .now)!
            let range = SurveyWeekWindow.pastRange(from: reference, calendar: calendar, lookbackDays: 56)!
            // start = anchor - 56, end = anchor - 1, so end - start == 55 days.
            let daysBetween = calendar.dateComponents([.day], from: range.start, to: range.end).day!
            #expect(daysBetween == 55)
        }
    }

    @Test func pastRangeNeverOverlapsCurrentWeekBlocks() {
        for offset in 0..<14 {
            let reference = calendar.date(byAdding: .day, value: offset, to: .now)!
            let range = SurveyWeekWindow.pastRange(from: reference, calendar: calendar)!
            let blocks = SurveyWeekWindow.currentWeekBlocks(from: reference, calendar: calendar)
            for block in blocks {
                #expect(range.end < block.weekStart)
            }
        }
    }
}
