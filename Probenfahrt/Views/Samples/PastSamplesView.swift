import SwiftUI

/// Past Proben reports grouped into Mon–Sun week blocks — same "Wochenblock"
/// idea as Umfragen's PastSurveysView. Includes the current week (so a day
/// is always reachable through its week, not just via the "today" Proben
/// tab) plus `weeksBack` further weeks. Only days with at least one report
/// are shown; weeks with nothing at all are skipped entirely.
struct PastSamplesView: View {
    let currentUser: User

    @State private var blocks: [SampleWeekWindow.WeekBlock] = []
    @State private var locations: [SampleLocation] = []
    @State private var reportsByDay: [Date: [SampleReport]] = [:]
    @State private var hasLoadedOnce = false

    private var samplesRepository: SamplesRepository { CloudKitSamplesRepository() }

    /// `reportsByDay` is keyed by `SampleReport.normalizedDay`-anchored
    /// values (UTC midnight of the Berlin day), but `day` here comes from
    /// `SampleWeekWindow.pastWeekBlocks`, which is anchored at
    /// device-local midnight — a different instant for the same calendar
    /// day. Re-normalize before every lookup so the two sides actually meet.
    private func hasReports(on day: Date) -> Bool {
        !(reportsByDay[SampleReport.normalizedDay(day)] ?? []).isEmpty
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
                        SampleDayCard(day: day, locations: locations, reports: reportsByDay[SampleReport.normalizedDay(day)] ?? [])
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

    /// Only replaces `locations`/`blocks`/`reportsByDay` on a fully
    /// successful load, and never clears them beforehand or on failure — a
    /// transient error on pull-to-refresh must not blank out previously
    /// shown weeks (mirrors the same fix in SurveysView/SamplesListView).
    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        do {
            let newLocations = try await samplesRepository.locations(groupID: groupID)
            // Blocks are ordered most-recent-first (see SampleWeekWindowTests),
            // so the earliest day is the last block's first day and the
            // latest is the first block's last day.
            let newBlocks = SampleWeekWindow.pastWeekBlocks(from: .now)
            var newReportsByDay: [Date: [SampleReport]] = [:]
            if let earliest = newBlocks.last?.days.first, let latest = newBlocks.first?.days.last {
                // One range query for the whole window instead of one
                // per day (used to be up to 56 sequential network calls).
                let allReports = try await samplesRepository.reports(groupID: groupID, from: earliest, to: latest)
                for report in allReports {
                    newReportsByDay[report.day, default: []].append(report)
                }
            }
            locations = newLocations
            blocks = newBlocks
            reportsByDay = newReportsByDay
        } catch {
            // Keep showing the last known-good weeks instead of blanking
            // them on a transient reload failure.
        }
        hasLoadedOnce = true
    }
}
