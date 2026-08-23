import SwiftUI
import SwiftData

struct SamplesListView: View {
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @Environment(DevModeStore.self) private var devMode
    @State private var selectedDay: Date = SampleReport.normalizedDay(.now)
    @State private var locations: [SampleLocation] = []
    @State private var reports: [SampleReport] = []

    private var samplesRepository: SamplesRepository { SwiftDataSamplesRepository(context: modelContext) }

    private var isToday: Bool {
        Calendar.current.isDate(selectedDay, inSameDayAs: .now)
    }

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
                            hasSamplesRow(entry)
                        }
                    } header: {
                        Label("Proben vorhanden (\(withSamples.count))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if !withoutSamples.isEmpty {
                    Section {
                        ForEach(withoutSamples) { entry in
                            noSamplesRow(entry)
                        }
                    } header: {
                        Text("Keine Proben (\(withoutSamples.count))")
                    }
                }

                if locations.isEmpty {
                    ContentUnavailableView("Keine Apotheken/Labore", systemImage: "cross.vial")
                } else if withSamples.isEmpty && withoutSamples.isEmpty {
                    ContentUnavailableView(
                        isToday ? "Heute noch keine Meldungen" : "Keine Meldungen an diesem Tag",
                        systemImage: "cross.vial"
                    )
                }
            }
            .navigationTitle("Proben")
            .safeAreaInset(edge: .top) { dayNavigator }
            .developerFeedbackOverlay(isActive: devMode.isActive, screen: "Proben", feature: "Standortliste", element: "Liste")
            .task(id: selectedDay) { await load() }
            .refreshable { await load() }
        }
    }

    private var dayNavigator: some View {
        HStack {
            Button {
                selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Vorheriger Tag")

            Spacer()

            VStack(spacing: 2) {
                Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month().locale(.app)))
                    .font(.subheadline.weight(.semibold))
                if !isToday {
                    Button("Heute") { selectedDay = SampleReport.normalizedDay(.now) }
                        .font(.caption)
                }
            }

            Spacer()

            Button {
                selectedDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Nächster Tag")
            .disabled(isToday)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func hasSamplesRow(_ entry: SampleDayGrouping.Entry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.location.name).font(.headline)
                Text(entry.location.address).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(entry.report.reportedAt.formatted(.dateTime.weekday(.wide).day().month().locale(.app)))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Label(
                    entry.report.statusNote.isEmpty ? "Proben vorhanden" : entry.report.statusNote,
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }

    private func noSamplesRow(_ entry: SampleDayGrouping.Entry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.location.name).font(.headline)
                Text(entry.location.address).font(.caption).foregroundStyle(.secondary)
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
        reports = (try? await samplesRepository.reports(groupID: groupID, day: selectedDay)) ?? []
    }
}
