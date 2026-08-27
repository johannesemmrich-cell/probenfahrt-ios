import Testing
import Foundation
@testable import Probenfahrt

struct SamplesReportGeneratorTests {
    @Test func aggregatesDaysWithSamplesPerLocation() {
        let groupID = UUID()
        let locationA = SampleLocation(groupID: groupID, name: "Apotheke A", address: "")
        let locationB = SampleLocation(groupID: groupID, name: "Apotheke B", address: "")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let reports = [
            SampleReport(locationID: locationA.id, groupID: groupID, day: .now, hasSamples: true),
            SampleReport(locationID: locationA.id, groupID: groupID, day: yesterday, hasSamples: true),
            SampleReport(locationID: locationB.id, groupID: groupID, day: .now, hasSamples: true),
        ]

        let lines = SamplesReportGenerator.generate(reports: reports, locations: [locationA, locationB])

        #expect(lines.count == 2)
        #expect(lines.first?.locationName == "Apotheke A")
        #expect(lines.first?.daysWithSamples == 2)
        #expect(lines.last?.locationName == "Apotheke B")
        #expect(lines.last?.daysWithSamples == 1)
    }

    @Test func ignoresReportsWithoutSamples() {
        let groupID = UUID()
        let location = SampleLocation(groupID: groupID, name: "Apotheke A", address: "")
        let reports = [SampleReport(locationID: location.id, groupID: groupID, day: .now, hasSamples: false)]

        let lines = SamplesReportGenerator.generate(reports: reports, locations: [location])

        #expect(lines.isEmpty)
    }

    @Test func emptyReportsProduceEmptyReport() {
        let lines = SamplesReportGenerator.generate(reports: [], locations: [])
        #expect(lines.isEmpty)
    }

    @Test func ignoresReportsForUnknownLocations() {
        let reports = [SampleReport(locationID: UUID(), groupID: UUID(), day: .now, hasSamples: true)]
        let lines = SamplesReportGenerator.generate(reports: reports, locations: [])
        #expect(lines.isEmpty)
    }
}
