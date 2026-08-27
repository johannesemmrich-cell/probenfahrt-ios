import Testing
import Foundation
@testable import Probenfahrt

struct SampleWeekWindowTests {
    private let calendar = Calendar.current

    @Test func pastWeekBlocksReturnsExactlyWeeksBackBlocks() {
        for offset in 0..<14 {
            let reference = calendar.date(byAdding: .day, value: offset, to: .now)!
            let blocks = SampleWeekWindow.pastWeekBlocks(from: reference, calendar: calendar, weeksBack: 8)
            #expect(blocks.count == 8)
        }
    }

    @Test func everyBlockHasSevenMondayThroughSundayDays() {
        for offset in 0..<14 {
            let reference = calendar.date(byAdding: .day, value: offset, to: .now)!
            let blocks = SampleWeekWindow.pastWeekBlocks(from: reference, calendar: calendar)
            for block in blocks {
                #expect(block.days.count == 7)
                #expect(block.weekStart == block.days.first)
                #expect(block.weekEnd == block.days.last)
                #expect(calendar.component(.weekday, from: block.weekStart) == 2) // Monday
            }
        }
    }

    /// Today (or whatever `referenceDate` is) must always be reachable
    /// through its own week block — Proben's "today" tab has no separate
    /// week-block concept of its own, so PastSamplesView is the only place
    /// a day's week context shows up.
    @Test func firstBlockIsTheWeekContainingTheReferenceDate() {
        for offset in 0..<14 {
            let reference = calendar.date(byAdding: .day, value: offset, to: .now)!
            let blocks = SampleWeekWindow.pastWeekBlocks(from: reference, calendar: calendar)
            let referenceDay = calendar.startOfDay(for: reference)
            #expect(blocks[0].days.contains(referenceDay))
        }
    }

    @Test func blocksAreOrderedMostRecentFirstWithNoGapBetweenConsecutiveWeeks() {
        for offset in 0..<14 {
            let reference = calendar.date(byAdding: .day, value: offset, to: .now)!
            let blocks = SampleWeekWindow.pastWeekBlocks(from: reference, calendar: calendar)
            for i in 0..<(blocks.count - 1) {
                let expectedNext = calendar.date(byAdding: .day, value: -7, to: blocks[i].weekStart)!
                #expect(blocks[i + 1].weekStart == expectedNext)
            }
        }
    }
}
