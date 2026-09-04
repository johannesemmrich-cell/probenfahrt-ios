import SwiftUI

/// Admin-only "Apotheken verwalten" screen (BACKLOG #3): create QR-only
/// pharmacy locations that never install the app or sign in, show/share
/// each one's QR code, and report Ja/Nein on a pharmacy's behalf (e.g. if
/// they call in instead of scanning).
/// TODO(Backlog #2): not technically access-controlled yet, same as the
/// rest of the Admin section — reachable via the "Als Admin anzeigen" dev
/// toggle.
struct PharmacyManagementView: View {
    let currentUser: User

    @State private var locations: [SampleLocation] = []
    @State private var todaysReports: [UUID: SampleReport] = [:]
    @State private var isShowingAddSheet = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var samplesRepository: SamplesRepository { CloudKitSamplesRepository() }
    private var today: Date { SampleReport.normalizedDay(.now) }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if locations.isEmpty {
                ContentUnavailableView {
                    Label("Keine Apotheken", systemImage: "cross.vial")
                } description: {
                    Text("Lege eine Apotheke an, um ihr einen eigenen QR-Code für den Web-Check-in zu geben.")
                } actions: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Testapotheke Warendorf anlegen") {
                            Task { await addLocation(name: "Warendorf", address: "", usesQRCheckIn: true) }
                        }
                    }
                }
            } else {
                ForEach(locations) { location in
                    NavigationLink {
                        PharmacyDetailView(location: location) {
                            await load()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(location.name)
                                    if location.usesQRCheckIn {
                                        Image(systemName: "qrcode")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if !location.address.isEmpty {
                                    Text(location.address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            statusBadge(for: location)
                        }
                    }
                }
            }
        }
        .navigationTitle("Apotheken verwalten")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddPharmacySheet { name, address, usesQRCheckIn in
                Task { await addLocation(name: name, address: address, usesQRCheckIn: usesQRCheckIn) }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func statusBadge(for location: SampleLocation) -> some View {
        if let report = todaysReports[location.id] {
            Image(systemName: report.hasSamples ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(report.hasSamples ? .green : .secondary)
        } else {
            Text("Keine Meldung")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        errorMessage = nil
        do {
            locations = try await samplesRepository.locations(groupID: groupID)
            let reports = try await samplesRepository.reports(groupID: groupID, day: today)
            todaysReports = Dictionary(uniqueKeysWithValues: reports.map { ($0.locationID, $0) })
        } catch {
            errorMessage = "Laden fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func addLocation(name: String, address: String, usesQRCheckIn: Bool) async {
        guard let groupID = currentUser.groupID else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await samplesRepository.createLocation(
                groupID: groupID,
                name: trimmedName,
                address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                usesQRCheckIn: usesQRCheckIn
            )
            await load()
        } catch {
            errorMessage = "Anlegen fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}

private struct AddPharmacySheet: View {
    let onSave: (String, String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var usesQRCheckIn = true

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name der Apotheke/des Briefkastens", text: $name)
                TextField("Adresse (optional)", text: $address)

                Section {
                    Toggle("Web-Check-in per QR-Code", isOn: $usesQRCheckIn)
                } footer: {
                    Text(usesQRCheckIn
                        ? "Die Apotheke scannt ihren eigenen QR-Code und meldet sich selbst über die Web-Seite."
                        : "Kein QR-Code — du meldest Ja/Nein für diese Apotheke selbst, z. B. wenn sie anruft statt zu scannen.")
                }
            }
            .navigationTitle("Apotheke hinzufügen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        onSave(name, address, usesQRCheckIn)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct PharmacyDetailView: View {
    let location: SampleLocation
    let onChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var webLinkStore = PharmacyWebLinkStore()
    @State private var currentReport: SampleReport?
    @State private var isSaving = false
    @State private var qrImage: UIImage?
    @State private var isShowingDeleteConfirmation = false
    @State private var errorMessage: String?

    private var samplesRepository: SamplesRepository { CloudKitSamplesRepository() }
    private var checkInURLString: String { webLinkStore.checkInURL(token: location.token) }

    @ViewBuilder
    private var statusCard: some View {
        HStack(spacing: 14) {
            if isSaving {
                ProgressView()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: statusIconName)
                    .font(.system(size: 30))
                    .foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.headline)
                if let currentReport {
                    Text("Gemeldet um \(currentReport.reportedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .animation(.default, value: currentReport?.hasSamples)
        .animation(.default, value: isSaving)
    }

    private var statusIconName: String {
        guard let currentReport else { return "questionmark.circle" }
        return currentReport.hasSamples ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var statusColor: Color {
        guard let currentReport else { return .secondary }
        return currentReport.hasSamples ? .green : .secondary
    }

    private var statusTitle: String {
        guard let currentReport else { return "Heute noch keine Meldung" }
        return currentReport.hasSamples ? "Proben vorhanden" : "Keine Proben"
    }

    var body: some View {
        Form {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if location.usesQRCheckIn {
                Section("QR-Code") {
                    VStack(spacing: 16) {
                        if let qrImage {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 220, height: 220)
                        }
                        Text(checkInURLString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if let qrImage {
                            ShareLink(
                                item: Image(uiImage: qrImage),
                                preview: SharePreview("QR-Code \(location.name)", image: Image(uiImage: qrImage))
                            ) {
                                Label("QR-Code teilen/drucken", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Section("Web-Adresse für QR-Codes") {
                    TextField("Basis-URL", text: $webLinkStore.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Text("Für echtes Scannen per Handy: statt localhost die LAN-IP des Macs eintragen, z.B. http://192.168.1.23:8080. Gilt für alle QR-Codes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text("Diese Apotheke hat keinen QR-Code — sie meldet sich nicht selbst, du trägst Ja/Nein hier manuell ein.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Heute manuell melden") {
                statusCard

                Button {
                    Task { await setStatus(true) }
                } label: {
                    Label("Ja, Proben vorhanden", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isSaving || currentReport?.hasSamples == true)

                Button {
                    Task { await setStatus(false) }
                } label: {
                    Label("Keine Proben", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSaving || currentReport?.hasSamples == false)
            }

            Section {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Label("Apotheke löschen", systemImage: "trash")
                }
            }
        }
        .navigationTitle(location.name)
        .confirmationDialog(
            "\(location.name) wirklich löschen?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                Task { await deleteLocation() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle bisherigen Proben-Meldungen dieser Apotheke werden mitgelöscht. Das lässt sich nicht rückgängig machen.")
        }
        .task {
            if location.usesQRCheckIn { updateQRImage() }
            await loadReport()
        }
        .onChange(of: webLinkStore.baseURL) {
            updateQRImage()
        }
    }

    private func updateQRImage() {
        qrImage = QRCodeGenerator.image(for: checkInURLString)
    }

    private func loadReport() async {
        currentReport = try? await samplesRepository.report(locationID: location.id, day: SampleReport.normalizedDay(.now))
    }

    private func setStatus(_ hasSamples: Bool) async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await samplesRepository.setHasSamples(hasSamples, locationID: location.id, day: SampleReport.normalizedDay(.now))
            await loadReport()
            await onChanged()
        } catch {
            errorMessage = "Melden fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func deleteLocation() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await samplesRepository.deleteLocation(id: location.id, ownerUserID: location.ownerUserID)
            await onChanged()
            dismiss()
        } catch {
            errorMessage = "Löschen fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
