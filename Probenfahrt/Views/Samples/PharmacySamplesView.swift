import SwiftUI
import SwiftData

/// The entire Proben experience for a self-service pharmacy/supplier account
/// (AccountKind.pharmacy): today's date, and one tap to say whether they
/// currently have samples. Nothing else — the lab team sees the result in
/// the regular SamplesListView. Also used by DevModeStore's
/// "Proben (Test)"-Tab preview, in which case `currentUser` is a lab-team
/// account and its own location is created on demand.
struct PharmacySamplesView: View {
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @Environment(DevModeStore.self) private var devMode
    @State private var location: SampleLocation?
    @State private var isSaving = false

    private var samplesRepository: SamplesRepository { SwiftDataSamplesRepository(context: modelContext) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month().year().locale(.app)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Habt ihr heute Proben?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    Button {
                        Task { await setStatus(true) }
                    } label: {
                        Label("Ja, wir haben Proben", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                    .disabled(isSaving || location?.hasSamples == true)

                    Button {
                        Task { await setStatus(false) }
                    } label: {
                        Label("Keine Proben", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isSaving || location?.hasSamples == false)
                }
                .padding(.horizontal, 24)

                if let location {
                    Text(location.hasSamples ? "Aktueller Status: Proben vorhanden" : "Aktueller Status: Keine Proben")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Spacer()
            }
            .navigationTitle(currentUser.name)
            .developerFeedbackOverlay(isActive: devMode.isActive, screen: "Proben (Apotheke)", feature: "Status", element: "Buttons")
            .task { await load() }
        }
    }

    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        location = try? await samplesRepository.findOrCreateLocation(ownerUserID: currentUser.id, groupID: groupID, name: currentUser.name)
    }

    private func setStatus(_ hasSamples: Bool) async {
        guard let location else { return }
        isSaving = true
        defer { isSaving = false }
        try? await samplesRepository.setHasSamples(hasSamples, locationID: location.id)
        await load()
    }
}
