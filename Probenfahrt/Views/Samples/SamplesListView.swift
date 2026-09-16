import SwiftUI

struct SamplesListView: View {
    let currentUser: User

    @Environment(DevModeStore.self) private var devMode
    @State private var locations: [SampleLocation] = []
    @State private var reports: [SampleReport] = []

    private var samplesRepository: SamplesRepository { CloudKitSamplesRepository() }

    private var withSamples: [SampleDayGrouping.Entry] {
        SampleDayGrouping.withSamples(locations: locations, reports: reports)
    }

    private var withoutSamples: [SampleDayGrouping.Entry] {
        SampleDayGrouping.withoutSamples(locations: locations, reports: reports)
    }

    var body: some View {
        NavigationStack {
            List {
                if !withSamples.isEmpty {
                    Section {
                        ForEach(withSamples) { entry in
                            SampleLocationRow(entry: entry, hasSamples: true)
                        }
                    } header: {
                        Label("Proben vorhanden (\(withSamples.count))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if !withoutSamples.isEmpty {
                    Section {
                        ForEach(withoutSamples) { entry in
                            SampleLocationRow(entry: entry, hasSamples: false)
                        }
                    } header: {
                        Text("Keine Proben (\(withoutSamples.count))")
                    }
                }

                if locations.isEmpty {
                    ContentUnavailableView("Keine Apotheken/Briefkästen", systemImage: "cross.vial")
                } else if withSamples.isEmpty && withoutSamples.isEmpty {
                    ContentUnavailableView("Heute noch keine Meldungen", systemImage: "cross.vial")
                }
            }
            .navigationTitle("Proben")
            .developerFeedbackOverlay(isActive: devMode.isActive, screen: "Proben", feature: "Standortliste", element: "Liste")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Vergangen") {
                        PastSamplesView(currentUser: currentUser)
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    /// Only overwrites existing data on success — a transient failure of
    /// either fetch should leave the previously shown list intact rather
    /// than blanking it. (Fetching both concurrently via `async let` would
    /// need `SamplesRepository` to be `Sendable`, which its `@MainActor`
    /// isolation deliberately isn't — not worth the architectural change for
    /// two calls that are already cheap.)
    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        if let newLocations = try? await samplesRepository.locations(groupID: groupID) {
            locations = newLocations
        }
        if let newReports = try? await samplesRepository.reports(groupID: groupID, day: SampleReport.normalizedDay(.now)) {
            reports = newReports
        }
    }
}
