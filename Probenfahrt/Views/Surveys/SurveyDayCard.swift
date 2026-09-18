import SwiftUI

struct SurveyDayCard: View {
    let row: SurveyDayRow
    let users: [User]
    let currentUser: User
    let onToggle: () async -> Void
    var onRowChanged: (SurveyDayRow) -> Void = { _ in }

    @Environment(AdminPreviewStore.self) private var adminPreview
    @Environment(DevModeStore.self) private var devMode

    private var isSignedIn: Bool {
        row.entries.contains { $0.userID == currentUser.id }
    }

    private var isLockedWithEntries: Bool {
        row.day.isLocked && !row.entries.isEmpty
    }

    private var isAdmin: Bool {
        isEffectiveAdmin(user: currentUser, adminPreview: adminPreview, devMode: devMode)
    }

    private var showsQuickToggle: Bool {
        !row.day.isLocked && shouldShowQuickToggle(for: row.day, user: currentUser, adminPreview: adminPreview, devMode: devMode)
    }

    /// Deliberately a styled label, not a second `NavigationLink` — a `List`
    /// row with two sibling `NavigationLink`s can push its destination twice
    /// from one tap (the row's own selection-forwarding plus the tapped
    /// link), which was exactly the "back needs two taps" bug this replaced.
    private var showsVerwaltenBadge: Bool {
        isAdmin && !showsQuickToggle
    }

    private var initials: [String] {
        row.entries.compactMap { entry in
            users.first { $0.id == entry.userID }?.abbreviation
        }
    }

    var body: some View {
        HStack {
            NavigationLink {
                SurveyDayDetailView(row: row, users: users, currentUser: currentUser, onRowChanged: onRowChanged)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(row.day.date.formatted(.dateTime.weekday(.wide).day().month().locale(.app)))
                                .font(.headline)
                                .foregroundStyle(.primary)

                            if row.entries.count > 1 {
                                Text("!")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.red)
                            } else if row.entries.count == 1 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }

                        if row.day.isLocked {
                            HStack(spacing: 4) {
                                Label(lockLabel, systemImage: "lock.fill")
                                if isLockedWithEntries {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(isLockedWithEntries ? .orange : .secondary)
                        } else if initials.isEmpty {
                            Text("Noch niemand eingetragen")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(initials.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if showsVerwaltenBadge {
                        Spacer()
                        Text("Verwalten")
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            if showsQuickToggle {
                Spacer()
                Button {
                    Task { await onToggle() }
                } label: {
                    Text(isSignedIn ? "Austragen" : "Eintragen")
                }
                .buttonStyle(.bordered)
                .tint(isSignedIn ? .red : .accentColor)
            }
        }
        .opacity(row.day.isLocked && row.entries.isEmpty ? 0.5 : 1)
        .padding(.vertical, 4)
    }

    private var lockLabel: String {
        let reason = row.day.lockReason ?? ""
        return reason.isEmpty ? "Gesperrt" : reason
    }
}
