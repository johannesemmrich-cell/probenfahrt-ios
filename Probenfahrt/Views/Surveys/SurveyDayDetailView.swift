import SwiftUI

struct SurveyDayDetailView: View {
    let users: [User]
    let currentUser: User
    var onRowChanged: (SurveyDayRow) -> Void = { _ in }

    @Environment(AdminPreviewStore.self) private var adminPreview
    @Environment(DevModeStore.self) private var devMode

    @State private var day: SurveyDay
    @State private var entries: [SurveyEntry]
    @State private var errorMessage: String?
    @State private var entryHapticPulse = 0
    @State private var monthEntries: [SurveyEntryWithDate] = []

    private let surveyRepository: SurveyRepository = CloudKitSurveyRepository()

    init(row: SurveyDayRow, users: [User], currentUser: User, onRowChanged: @escaping (SurveyDayRow) -> Void = { _ in }) {
        self.users = users
        self.currentUser = currentUser
        self.onRowChanged = onRowChanged
        _day = State(initialValue: row.day)
        _entries = State(initialValue: row.entries)
    }

    private var isAdmin: Bool { isEffectiveAdmin(user: currentUser, adminPreview: adminPreview, devMode: devMode) }

    private var signedInUserIDs: Set<UUID> {
        Set(entries.compactMap(\.userID))
    }

    private var names: [String] {
        entries
            .compactMap { entry in users.first { $0.id == entry.userID }?.name }
            .sorted()
    }

    private var sortedUsers: [User] {
        users.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var currentMonthInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: .now) ?? DateInterval(start: .now, duration: 0)
    }

    private func tripCountThisMonth(for user: User) -> Int {
        MemberStatsCalculator.tripCount(for: user.id, entries: monthEntries, in: currentMonthInterval)
    }

    var body: some View {
        List {
            if isAdmin {
                // TODO(Backlog #2): admin-only action, not technically enforced yet —
                // reachable by anyone via the "Als Admin anzeigen" dev toggle.
                Section {
                    if sortedUsers.isEmpty {
                        Text("Keine Mitglieder in der Gruppe").foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedUsers) { user in
                            Button {
                                Task { await toggleEntry(for: user) }
                            } label: {
                                HStack {
                                    Text(user.name).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: signedInUserIDs.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(signedInUserIDs.contains(user.id) ? .green : .secondary)
                                }
                            }
                            .contextMenu {
                                Button(signedInUserIDs.contains(user.id) ? "Austragen" : "Eintragen") {
                                    Task { await toggleEntry(for: user) }
                                }
                            } preview: {
                                MemberMonthlyTripsPreview(userName: user.name, tripCount: tripCountThisMonth(for: user))
                            }
                        }
                    }
                } header: {
                    Text("Teilnehmer verwalten")
                } footer: {
                    Text(day.isLocked
                         ? "Tag ist gesperrt. Als Admin kannst du trotzdem Teilnehmer ein-/austragen."
                         : "Tippe auf eine Person, um sie für diesen Tag ein- oder auszutragen. Lange drücken zeigt die Fahrten diesen Monat.")
                }
            } else {
                Section("Eingetragen") {
                    if names.isEmpty {
                        Text("Noch niemand eingetragen").foregroundStyle(.secondary)
                    } else {
                        ForEach(names, id: \.self) { name in
                            Text(name)
                        }
                    }
                }
            }

            if isAdmin {
                Section("Admin") {
                    Button(day.isLocked ? "Sperre aufheben" : "Tag sperren") {
                        Task { await toggleLock() }
                    }
                    .foregroundStyle(day.isLocked ? Color.primary : Color.red)
                }
            }
        }
        .navigationTitle(day.date.formatted(.dateTime.weekday(.wide).day().month().locale(.app)))
        .navigationBarTitleDisplayMode(.inline)
        .alert("Fehler", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sensoryFeedback(.impact, trigger: entryHapticPulse)
        .sensoryFeedback(trigger: day.isLocked) { _, isLocked in isLocked ? .warning : .impact }
        .sensoryFeedback(.error, trigger: errorMessage) { _, newValue in newValue != nil }
        .task {
            guard isAdmin, let groupID = currentUser.groupID else { return }
            let calendar = Calendar.current
            let month = calendar.component(.month, from: .now)
            let year = calendar.component(.year, from: .now)
            monthEntries = (try? await surveyRepository.entriesWithDates(inMonth: month, year: year, groupID: groupID)) ?? []
        }
    }

    /// Admin path: flips the row immediately (optimistic) instead of waiting
    /// on the CloudKit round trip, and never re-fetches on success — the new
    /// state is already known locally. `bypassLock: true` is safe here since
    /// this whole section only renders `if isAdmin`.
    private func toggleEntry(for user: User) async {
        let isSignedIn = signedInUserIDs.contains(user.id)
        let previousEntries = entries
        if isSignedIn {
            entries.removeAll { $0.userID == user.id }
        } else {
            entries.append(SurveyEntry(surveyDayID: day.id, userID: user.id, groupID: user.groupID))
        }
        onRowChanged(SurveyDayRow(day: day, entries: entries))
        entryHapticPulse += 1
        do {
            if isSignedIn {
                try await surveyRepository.signOut(userID: user.id, dayID: day.id)
            } else {
                try await surveyRepository.signIn(userID: user.id, dayID: day.id, bypassLock: true)
            }
        } catch {
            entries = previousEntries
            onRowChanged(SurveyDayRow(day: day, entries: entries))
            errorMessage = "Die Änderung konnte nicht gespeichert werden.\n\nFehlerdetails: \(error)"
        }
    }

    private func toggleLock() async {
        let newValue = !day.isLocked
        let newReason = newValue ? "Wird an diesem Tag nicht gefahren" : nil
        let previousLocked = day.isLocked
        let previousReason = day.lockReason
        day.isLocked = newValue
        day.lockReason = newReason
        onRowChanged(SurveyDayRow(day: day, entries: entries))
        do {
            try await surveyRepository.setLocked(newValue, reason: newReason, dayID: day.id)
        } catch {
            day.isLocked = previousLocked
            day.lockReason = previousReason
            onRowChanged(SurveyDayRow(day: day, entries: entries))
            errorMessage = "Die Änderung konnte nicht gespeichert werden.\n\nFehlerdetails: \(error)"
        }
    }
}

private struct MemberMonthlyTripsPreview: View {
    let userName: String
    let tripCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(userName)
                .font(.headline)
            Text("\(tripCount) \(tripCount == 1 ? "Fahrt" : "Fahrten") diesen Monat")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
