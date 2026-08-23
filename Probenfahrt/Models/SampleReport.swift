import Foundation
import SwiftData

/// One calendar day's yes/no answer from a single SampleLocation. A location
/// gets at most one report per day, updated in place if it changes its mind
/// the same day. Keeping these as separate rows (instead of overwriting a
/// single status field on SampleLocation) is what lets the Proben tab show
/// only today's reports and also browse past days.
@Model
final class SampleReport {
    var id: UUID = UUID()
    var locationID: UUID = UUID()
    var groupID: UUID?
    var day: Date = Date.now
    var hasSamples: Bool = false
    var statusNote: String = ""
    var reportedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        locationID: UUID,
        groupID: UUID?,
        day: Date,
        hasSamples: Bool,
        statusNote: String = "",
        reportedAt: Date = .now
    ) {
        self.id = id
        self.locationID = locationID
        self.groupID = groupID
        self.day = Self.normalizedDay(day)
        self.hasSamples = hasSamples
        self.statusNote = statusNote
        self.reportedAt = reportedAt
    }

    static func normalizedDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}
