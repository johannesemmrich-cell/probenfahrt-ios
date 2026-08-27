import Foundation

enum SamplesReportGenerator {
    struct ReportLine: Identifiable {
        var id: UUID { locationID }
        let locationID: UUID
        let locationName: String
        let daysWithSamples: Int
    }

    /// Aggregates, per Apotheke/Labor, how many days within the given
    /// reports had samples — the Proben equivalent of
    /// MonthlyReportGenerator's trip counts, e.g.
    /// "Apotheke Sonnenschein: 12 Tage mit Proben". Sorted by day count
    /// descending, then by name.
    static func generate(reports: [SampleReport], locations: [SampleLocation]) -> [ReportLine] {
        let locationByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
        var counts: [UUID: Int] = [:]
        for report in reports where report.hasSamples {
            counts[report.locationID, default: 0] += 1
        }
        return counts.compactMap { locationID, count -> ReportLine? in
            guard let location = locationByID[locationID] else { return nil }
            return ReportLine(locationID: locationID, locationName: location.name, daysWithSamples: count)
        }
        .sorted { lhs, rhs in
            if lhs.daysWithSamples != rhs.daysWithSamples {
                return lhs.daysWithSamples > rhs.daysWithSamples
            }
            return lhs.locationName < rhs.locationName
        }
    }
}
