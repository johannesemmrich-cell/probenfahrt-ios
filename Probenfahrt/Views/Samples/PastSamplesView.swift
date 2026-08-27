import SwiftUI
import SwiftData

/// Past Proben reports grouped into Mon–Sun week blocks — same "Wochenblock"
/// idea as Umfragen's PastSurveysView. Includes the current week (so a day
/// is always reachable through its week, not just via the "today" Proben
/// tab) plus `weeksBack` further weeks. Only days with at least one report
/// are shown; weeks with nothing at all are skipped entirely.
struct PastSamplesView: View {
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @State private var blocks: [SampleWeekWindow.WeekBlock] = []
    @State private var locations: [SampleLocation] = []
    @State private var reportsByDay: [Date: [SampleReport]] = [:]
    @State private var hasLoadedOnce = false

    private var samplesRepository: SamplesRepository { SwiftDataSamplesRepository(context: modelContext) }

    private func hasReports(on day: Date) -> Bool {
        !(reportsByDay[day] ?? []).isEmpty
    }

    private var nonEmptyBlocks: [SampleWeekWindow.WeekBlock] {
        blocks.filter { block in block.days.contains(where: hasReports) }
    }

    var body: some View {
        List {
            if nonEmptyBlocks.isEmpty && hasLoadedOnce {
                Text("Keine vergangenen Proben im Zeitraum.")
                    .foregroundStyle(.secondary)
            }
            ForEach(nonEmptyBlocks) { block in
                Section {
                    ForEach(block.days.filter(hasReports), id: \.self) { day in
                        SampleDayCard(day: day, locations: locations, reports: reportsByDay[day] ?? [])
                    }
                } header: {
                    SampleWeekHeader(block: block)
                }
            }
        }
        .navigationTitle("Vergangene Proben")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        do {
            locations = try await samplesRepository.locations(groupID: groupID)
            let newBlocks = SampleWeekWindow.pastWeekBlocks(from: .now)
            var newReportsByDay: [Date: [SampleReport]] = [:]
            for block in newBlocks {
                for day in block.days {
                    newReportsByDay[day] = try await samplesRepository.reports(groupID: groupID, day: day)
                }
            }
            blocks = newBlocks
            reportsByDay = newReportsByDay
        } catch {
            blocks = []
            reportsByDay = [:]
        }
        hasLoadedOnce = true
    }
}
