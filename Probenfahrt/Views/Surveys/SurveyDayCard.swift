import SwiftUI

struct SurveyDayCard: View {
    let row: SurveyDayRow
    let users: [User]
    let currentUser: User
    let onToggle: () async -> Void

    private var isSignedIn: Bool {
        row.entries.contains { $0.userID == currentUser.id }
    }

    private var initials: [String] {
        row.entries.compactMap { entry in
            users.first { $0.id == entry.userID }?.abbreviation
        }
    }

    var body: some View {
        HStack {
            NavigationLink {
                SurveyDayDetailView(row: row, users: users, currentUser: currentUser)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.day.date.formatted(.dateTime.weekday(.wide).day().month().locale(.app)))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if row.day.isLocked {
                        Label(lockLabel, systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            }

            Spacer()

            if !row.day.isLocked {
                Button {
                    Task { await onToggle() }
                } label: {
                    Text(isSignedIn ? "Austragen" : "Eintragen")
                }
                .buttonStyle(.bordered)
                .tint(isSignedIn ? .red : .accentColor)
            }
        }
        .opacity(row.day.isLocked ? 0.5 : 1)
        .padding(.vertical, 4)
    }

    private var lockLabel: String {
        let reason = row.day.lockReason ?? ""
        return reason.isEmpty ? "Gesperrt" : reason
    }
}
