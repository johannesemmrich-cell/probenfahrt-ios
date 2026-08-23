import Foundation

/// Pure join between a group's Apotheke/Labor identities and their reports
/// for one calendar day. Locations without a report for the requested day
/// are dropped entirely rather than shown as a third bucket, so a day with
/// no reports at all renders as a simple empty state.
enum SampleDayGrouping {
    struct Entry: Identifiable {
        let location: SampleLocation
        let report: SampleReport
        var id: UUID { location.id }
    }

    static func withSamples(locations: [SampleLocation], reports: [SampleReport]) -> [Entry] {
        entries(locations: locations, reports: reports, hasSamples: true)
    }

    static func withoutSamples(locations: [SampleLocation], reports: [SampleReport]) -> [Entry] {
        entries(locations: locations, reports: reports, hasSamples: false)
    }

    private static func entries(locations: [SampleLocation], reports: [SampleReport], hasSamples: Bool) -> [Entry] {
        let reportsByLocationID = Dictionary(uniqueKeysWithValues: reports.map { ($0.locationID, $0) })
        return locations
            .compactMap { location -> Entry? in
                guard let report = reportsByLocationID[location.id], report.hasSamples == hasSamples else { return nil }
                return Entry(location: location, report: report)
            }
            .sorted { $0.location.name.localizedCompare($1.location.name) == .orderedAscending }
    }
}
