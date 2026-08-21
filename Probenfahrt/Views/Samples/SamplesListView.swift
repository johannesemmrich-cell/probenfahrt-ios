import SwiftUI
import SwiftData

struct SamplesListView: View {
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @Environment(DevModeStore.self) private var devMode
    @State private var locations: [SampleLocation] = []

    private var samplesRepository: SamplesRepository { SwiftDataSamplesRepository(context: modelContext) }

    private var withSamples: [SampleLocation] {
        locations.filter { $0.hasSamples }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var withoutSamples: [SampleLocation] {
        locations.filter { !$0.hasSamples }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if !withSamples.isEmpty {
                    Section {
                        ForEach(withSamples) { location in
                            hasSamplesRow(location)
                        }
                    } header: {
                        Label("Proben vorhanden (\(withSamples.count))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if !withoutSamples.isEmpty {
                    Section {
                        ForEach(withoutSamples) { location in
                            noSamplesRow(location)
                        }
                    } header: {
                        Text("Keine Proben (\(withoutSamples.count))")
                    }
                }

                if locations.isEmpty {
                    ContentUnavailableView("Keine Apotheken/Labore", systemImage: "cross.vial")
                }
            }
            .navigationTitle("Proben")
            .developerFeedbackOverlay(isActive: devMode.isActive, screen: "Proben", feature: "Standortliste", element: "Liste")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func hasSamplesRow(_ location: SampleLocation) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name).font(.headline)
                Text(location.address).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(location.updatedAt.formatted(.dateTime.weekday(.wide).day().month().locale(.app)))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Label(
                    location.statusNote.isEmpty ? "Proben vorhanden" : location.statusNote,
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }

    private func noSamplesRow(_ location: SampleLocation) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name).font(.headline)
                Text(location.address).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Keine Proben")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary))
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        locations = (try? await samplesRepository.locations(groupID: groupID)) ?? []
    }
}
