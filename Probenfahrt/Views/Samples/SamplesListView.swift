import SwiftUI
import SwiftData

struct SamplesListView: View {
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @State private var locations: [SampleLocation] = []

    private var samplesRepository: SamplesRepository { SwiftDataSamplesRepository(context: modelContext) }

    var body: some View {
        List(locations) { location in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name).font(.headline)
                    Text(location.address).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if location.hasSamples {
                    Label(
                        location.statusNote.isEmpty ? "Ja, wir haben Proben" : location.statusNote,
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                }
            }
            .opacity(location.hasSamples ? 1 : 0.4)
            .padding(.vertical, 2)
        }
        .navigationTitle("Proben")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        locations = (try? await samplesRepository.locations(groupID: groupID)) ?? []
    }
}
