import SwiftUI

/// Admin-only monthly Proben report as a shareable PDF, e.g.
/// "Apotheke Sonnenschein: 12 Tage mit Proben" — the Proben equivalent of
/// AdminReportView's Fahrten-Auswertung.
/// TODO(Backlog #2): not technically access-controlled yet — reachable via
/// the "Als Admin anzeigen" dev toggle.
struct SamplesReportView: View {
    let currentUser: User

    @State private var referenceMonth = Calendar.current.startOfDay(for: .now)
    @State private var lines: [SamplesReportGenerator.ReportLine] = []
    @State private var pdfURL: URL?

    private var samplesRepository: SamplesRepository { CloudKitSamplesRepository() }

    private var monthTitle: String {
        referenceMonth.formatted(.dateTime.month(.wide).year().locale(.app))
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Button { shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(monthTitle).font(.headline)
                    Spacer()
                    Button { shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.plain)
            }

            Section("Tage mit Proben pro Apotheke/Briefkasten") {
                if lines.isEmpty {
                    Text("Keine Proben-Meldungen in diesem Monat.").foregroundStyle(.secondary)
                } else {
                    ForEach(lines) { line in
                        HStack {
                            Text(line.locationName)
                            Spacer()
                            Text("\(line.daysWithSamples) \(line.daysWithSamples == 1 ? "Tag" : "Tage")")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let pdfURL {
                Section {
                    ShareLink(item: pdfURL, preview: SharePreview("Proben-Auswertung \(monthTitle)")) {
                        Label("PDF teilen/speichern", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle("Proben-Auswertung")
        .task(id: referenceMonth) { await load() }
    }

    private func shiftMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: referenceMonth) {
            referenceMonth = newDate
        }
    }

    /// Only replaces `lines`/`pdfURL` on a fully successful load — this
    /// `.task(id:)` re-fires on every month-navigation tap, so a transient
    /// failure must not blank an already-generated report.
    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        let calendar = Calendar.current
        let month = calendar.component(.month, from: referenceMonth)
        let year = calendar.component(.year, from: referenceMonth)
        do {
            let locations = try await samplesRepository.locations(groupID: groupID)
            let reports = try await samplesRepository.reports(groupID: groupID, inMonth: month, year: year)
            let newLines = SamplesReportGenerator.generate(reports: reports, locations: locations)
            let data = PDFReportRenderer.renderSamplesReport(title: "Proben-Auswertung \(monthTitle)", lines: newLines)
            lines = newLines
            pdfURL = writeTempPDF(data: data)
        } catch {
            // Keep showing the last known-good report instead of blanking it.
        }
    }

    private func writeTempPDF(data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Proben-\(monthTitle).pdf")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
