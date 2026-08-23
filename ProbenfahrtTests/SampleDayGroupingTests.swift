import Testing
import Foundation
@testable import Probenfahrt

struct SampleDayGroupingTests {
    @Test func onlyLocationsWithAReportForThatDayAppear() {
        let groupID = UUID()
        let reported = SampleLocation(groupID: groupID, name: "Apotheke A", address: "")
        let unreported = SampleLocation(groupID: groupID, name: "Apotheke B", address: "")
        let report = SampleReport(locationID: reported.id, groupID: groupID, day: .now, hasSamples: true)

        let withSamples = SampleDayGrouping.withSamples(locations: [reported, unreported], reports: [report])
        let withoutSamples = SampleDayGrouping.withoutSamples(locations: [reported, unreported], reports: [report])

        #expect(withSamples.map(\.location.id) == [reported.id])
        #expect(withoutSamples.isEmpty)
    }

    @Test func splitsHasSamplesFromNoSamples() {
        let groupID = UUID()
        let locationA = SampleLocation(groupID: groupID, name: "Apotheke A", address: "")
        let locationB = SampleLocation(groupID: groupID, name: "Apotheke B", address: "")
        let reports = [
            SampleReport(locationID: locationA.id, groupID: groupID, day: .now, hasSamples: true),
            SampleReport(locationID: locationB.id, groupID: groupID, day: .now, hasSamples: false),
        ]

        let withSamples = SampleDayGrouping.withSamples(locations: [locationA, locationB], reports: reports)
        let withoutSamples = SampleDayGrouping.withoutSamples(locations: [locationA, locationB], reports: reports)

        #expect(withSamples.map(\.location.id) == [locationA.id])
        #expect(withoutSamples.map(\.location.id) == [locationB.id])
    }

    @Test func sortsAlphabeticallyByLocationName() {
        let groupID = UUID()
        let zebra = SampleLocation(groupID: groupID, name: "Zebra Apotheke", address: "")
        let anna = SampleLocation(groupID: groupID, name: "Anna Apotheke", address: "")
        let reports = [
            SampleReport(locationID: zebra.id, groupID: groupID, day: .now, hasSamples: true),
            SampleReport(locationID: anna.id, groupID: groupID, day: .now, hasSamples: true),
        ]

        let withSamples = SampleDayGrouping.withSamples(locations: [zebra, anna], reports: reports)

        #expect(withSamples.map(\.location.name) == ["Anna Apotheke", "Zebra Apotheke"])
    }

    @Test func reportFromADifferentDayIsIgnored() {
        let groupID = UUID()
        let location = SampleLocation(groupID: groupID, name: "Apotheke A", address: "")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let report = SampleReport(locationID: location.id, groupID: groupID, day: yesterday, hasSamples: true)

        // Simulates the repository only handing back reports matching the
        // selected day — grouping itself must not re-filter by date.
        let withSamples = SampleDayGrouping.withSamples(locations: [location], reports: [report])

        #expect(withSamples.map(\.location.id) == [location.id])
    }
}
