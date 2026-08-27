import SwiftUI
import SwiftData

struct SamplesListView: View {
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @Environment(DevModeStore.self) private var devMode
    @State private var locations: [SampleLocation] = []
    @State private var reports: [SampleReport] = []

    private var samplesRepository: SamplesRepository { SwiftDataSamplesRepository(context: modelContext) }

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
                    ContentUnavailableView("Keine Apotheken/Labore", systemImage: "cross.vial")
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

    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        locations = (try? await samplesRepository.locations(groupID: groupID)) ?? []
        reports = (try? await samplesRepository.reports(groupID: groupID, day: SampleReport.normalizedDay(.now))) ?? []
    }
}
