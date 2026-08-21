import SwiftUI
import SwiftData

/// Admin-only monthly trip report as a shareable PDF, e.g. "Johannes: 7 Fahrten".
/// TODO(Backlog #2): not technically access-controlled yet — reachable via the
/// "Als Admin anzeigen" dev toggle.
struct AdminReportView: View {
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @State private var referenceMonth = Calendar.current.startOfDay(for: .now)
    @State private var lines: [MonthlyReportGenerator.ReportLine] = []
    @State private var pdfURL: URL?

    private var surveyRepository: SurveyRepository { SwiftDataSurveyRepository(context: modelContext) }
    private var userRepository: UserRepository { SwiftDataUserRepository(context: modelContext) }

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
            }

            Section("Fahrten pro Person") {
                if lines.isEmpty {
                    Text("Keine Fahrten in diesem Monat.").foregroundStyle(.secondary)
                } else {
                    ForEach(lines) { line in
                        HStack {
                            Text(line.userName)
                            Spacer()
                            Text("\(line.tripCount) \(line.tripCount == 1 ? "Fahrt" : "Fahrten")")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let pdfURL {
                Section {
                    ShareLink(item: pdfURL, preview: SharePreview("Fahrten-Auswertung \(monthTitle)")) {
                        Label("PDF teilen/speichern", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle("Monatsauswertung")
        .task(id: referenceMonth) { await load() }
    }

    private func shiftMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: referenceMonth) {
            referenceMonth = newDate
        }
    }

    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        let calendar = Calendar.current
        let month = calendar.component(.month, from: referenceMonth)
        let year = calendar.component(.year, from: referenceMonth)
        do {
            let users = try await userRepository.allUsers(inGroup: groupID)
            let entries = try await surveyRepository.entriesWithDates(inMonth: month, year: year, groupID: groupID)
            lines = MonthlyReportGenerator.generate(entries: entries, users: users)
            let data = PDFReportRenderer.renderMonthlyReport(title: "Fahrten-Auswertung \(monthTitle)", lines: lines)
            pdfURL = writeTempPDF(data: data)
        } catch {
            lines = []
            pdfURL = nil
        }
    }

    private func writeTempPDF(data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Fahrten-\(monthTitle).pdf")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
