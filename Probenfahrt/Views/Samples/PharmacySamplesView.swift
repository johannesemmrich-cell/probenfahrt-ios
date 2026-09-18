import SwiftUI

/// The entire Proben experience for a self-service pharmacy/supplier account
/// (AccountKind.pharmacy): today's date, and one tap to say whether they
/// currently have samples. Nothing else — the lab team sees the result in
/// the regular SamplesListView.
struct PharmacySamplesView: View {
    let currentUser: User

    @Environment(DevModeStore.self) private var devMode
    @State private var location: SampleLocation?
    @State private var todaysReport: SampleReport?
    @State private var isSaving = false
    @State private var successPulse = 0
    @State private var errorMessage: String?

    private var samplesRepository: SamplesRepository { CloudKitSamplesRepository() }
    private var today: Date { SampleReport.normalizedDay(.now) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month().year().locale(.app)))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

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
                    .disabled(isSaving || todaysReport?.hasSamples == true)

                    Button {
                        Task { await setStatus(false) }
                    } label: {
                        Label("Keine Proben", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isSaving || todaysReport?.hasSamples == false)
                }
                .padding(.horizontal, 24)

                if let todaysReport {
                    Text(todaysReport.hasSamples ? "Aktueller Status: Proben vorhanden" : "Aktueller Status: Keine Proben")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()
                Spacer()
            }
            .navigationTitle(currentUser.name)
            .developerFeedbackOverlay(isActive: devMode.isActive, screen: "Proben (Apotheke)", feature: "Status", element: "Buttons")
            .sensoryFeedback(.success, trigger: successPulse)
            .sensoryFeedback(.error, trigger: errorMessage) { _, newValue in newValue != nil }
            .task { await load() }
        }
    }

    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        location = try? await samplesRepository.findOrCreateLocation(ownerUserID: currentUser.id, groupID: groupID, name: currentUser.name)
        guard let location else { return }
        todaysReport = try? await samplesRepository.report(locationID: location.id, day: today)
    }

    /// Sets `todaysReport` optimistically instead of waiting on a
    /// write-then-two-more-calls `load()` round trip (mirrors the same fix
    /// in SurveyDayDetailView.toggleEntry/toggleLock) — rolled back on
    /// failure.
    private func setStatus(_ hasSamples: Bool) async {
        guard let location else { return }
        errorMessage = nil
        let previousReport = todaysReport
        todaysReport = SampleReport(locationID: location.id, groupID: location.groupID, day: today, hasSamples: hasSamples)
        isSaving = true
        defer { isSaving = false }
        do {
            try await samplesRepository.setHasSamples(hasSamples, locationID: location.id, day: today)
            successPulse += 1
        } catch {
            todaysReport = previousReport
            errorMessage = "Melden fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
