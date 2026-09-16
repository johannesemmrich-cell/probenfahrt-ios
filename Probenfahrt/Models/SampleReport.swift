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

    /// Resolves the **Berlin** calendar day (hardcoded, not the device's
    /// ambient `Calendar.current`/`TimeZone.current`) and anchors it at
    /// **UTC** midnight, to match how the Apotheken-Web-Check-in Worker
    /// computes "today" (`todayLocal()` in web/worker/src/index.js: resolves
    /// the Berlin Y/M/D via `Intl.DateTimeFormat(timeZone: "Europe/Berlin")`,
    /// then anchors via `Date.UTC(y, m, d)`) — both Workers and the app must
    /// agree on the same absolute instant for "the same day" regardless of
    /// which one is doing the writing.
    ///
    /// Using `Calendar.current` here instead (device-ambient timezone) was
    /// tried first and found insufficient: it only agrees with the Workers'
    /// hardcoded Berlin day for devices whose timezone happens to be
    /// Europe/Berlin — a lab-team member's iPhone with automatic timezone
    /// while traveling outside Germany would compute a different calendar
    /// day near midnight, reintroducing the exact class of mismatch this
    /// function exists to eliminate. Hardcoding Berlin, like the Workers do,
    /// makes the result identical everywhere, independent of device
    /// timezone. Use `SampleReport.dayString(_:)`, not
    /// `CloudKitQuerying.localDayString`, to build a record ID from this
    /// value — see that method's doc comment for why.
    static func normalizedDay(_ date: Date) -> Date {
        var berlinCalendar = Calendar(identifier: .gregorian)
        berlinCalendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let components = berlinCalendar.dateComponents([.year, .month, .day], from: date)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        return utcCalendar.date(from: components) ?? date
    }

    /// Formats an already-`normalizedDay`-anchored Date as "yyyy-MM-dd", for
    /// building the deterministic per-day CKRecord.ID
    /// (`CloudKitSamplesRepository.reportRecordID`) — matches the Worker's
    /// `day.toISOString().slice(0, 10)`, which is likewise always UTC-based.
    /// Deliberately reads the components back via a **UTC** calendar, not
    /// `CloudKitQuerying.localDayString`'s device-local one: since
    /// `normalizedDay` already anchored this instant at UTC midnight of the
    /// intended Berlin day, re-extracting via UTC is a lossless round trip
    /// on any device, whereas re-extracting via the device's own timezone
    /// would shift the date by a day on any device with a negative UTC
    /// offset (e.g. traveling in the Americas), producing the wrong record
    /// ID even though the stored `day` field value itself stays correct.
    static func dayString(_ normalizedDay: Date) -> String {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let components = utcCalendar.dateComponents([.year, .month, .day], from: normalizedDay)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
