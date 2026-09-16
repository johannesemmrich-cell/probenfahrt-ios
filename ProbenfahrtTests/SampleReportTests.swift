import Testing
import Foundation
@testable import Probenfahrt

struct SampleReportTests {
    private func utcMidnight(year: Int, month: Int, day: Int) -> Date {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        return utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func berlinComponents(_ date: Date) -> DateComponents {
        var berlinCalendar = Calendar(identifier: .gregorian)
        berlinCalendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return berlinCalendar.dateComponents([.year, .month, .day], from: date)
    }

    /// Mirrors the Apotheken-Web-Check-in Worker's `todayLocal()`
    /// (web/worker/src/index.js): resolve the **Berlin** calendar day
    /// (hardcoded, not the device's ambient timezone), then anchor it at UTC
    /// midnight. A report written by the app and one written by the web
    /// check-in must produce the exact same `Date` for "the same day", or
    /// the field-based query that joins them silently never matches.
    @Test func normalizedDayAnchorsAtUTCMidnightForTheBerlinCalendarDay() {
        let components = berlinComponents(.now)
        let expected = utcMidnight(year: components.year!, month: components.month!, day: components.day!)
        #expect(SampleReport.normalizedDay(.now) == expected)
    }

    /// The concrete regression this guards: extracting the day via the
    /// device's ambient `Calendar.current` (the first, insufficient version
    /// of this fix) only agrees with the Worker for a device actually set to
    /// Europe/Berlin. 2026-06-15 23:30 UTC is already 2026-06-16 01:30 in
    /// Berlin (CEST, UTC+2) — a device set to UTC (or any zone that hasn't
    /// yet rolled to the 16th) would compute the wrong day under the old
    /// device-ambient approach, but must still resolve to the 16th here.
    @Test func normalizedDayUsesBerlinCalendarDayRegardlessOfDeviceTimezone() {
        let instant = utcMidnight(year: 2026, month: 6, day: 15)
            .addingTimeInterval(23 * 3600 + 30 * 60)
        let expected = utcMidnight(year: 2026, month: 6, day: 16)
        #expect(SampleReport.normalizedDay(instant) == expected)
    }

    /// Uses a hardcoded Europe/Berlin calendar to build the two probe
    /// instants, not `Calendar.current` — normalizedDay resolves the
    /// **Berlin** day regardless of the test machine's own timezone, so a
    /// machine-ambient 1am/11pm pair would only coincidentally land on the
    /// same Berlin day when the machine itself happens to be on Berlin time
    /// (e.g. this could pass locally but fail on a CI runner set to UTC).
    @Test func normalizedDayIsStableAcrossTimesOnTheSameBerlinCalendarDay() {
        var berlinCalendar = Calendar(identifier: .gregorian)
        berlinCalendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let morning = berlinCalendar.date(bySettingHour: 1, minute: 0, second: 0, of: .now)!
        let evening = berlinCalendar.date(bySettingHour: 23, minute: 0, second: 0, of: .now)!
        #expect(SampleReport.normalizedDay(morning) == SampleReport.normalizedDay(evening))
    }

    /// SampleReport.dayString must be a lossless round trip on ANY device
    /// timezone, since normalizedDay's result is already UTC-midnight of the
    /// intended day — re-extracting via `Calendar.current` (as
    /// CloudKitQuerying.localDayString does) would shift the date by a day
    /// on a negative-UTC-offset device, producing the wrong CKRecord.ID.
    @Test func dayStringRoundTripsTheIntendedDateRegardlessOfHowItIsConstructed() {
        let normalized = SampleReport.normalizedDay(.now)
        let components = berlinComponents(.now)
        let expected = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
        #expect(SampleReport.dayString(normalized) == expected)
    }

    /// The concrete regression this guards: anchoring at *local* midnight
    /// (the pre-fix behavior) fails this for any device timezone with a
    /// non-zero UTC offset — which is every device this app actually runs
    /// on (Germany).
    @Test func normalizedDayResultIsAlwaysExactlyMidnightInUTC() {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let resultComponents = utcCalendar.dateComponents([.hour, .minute, .second], from: SampleReport.normalizedDay(.now))
        #expect(resultComponents.hour == 0)
        #expect(resultComponents.minute == 0)
        #expect(resultComponents.second == 0)
    }
}
