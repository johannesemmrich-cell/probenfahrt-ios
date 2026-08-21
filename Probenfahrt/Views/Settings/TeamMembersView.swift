import SwiftUI
import SwiftData

/// Admin-only roster of lab-team members (pharmacy accounts aren't listed
/// here — they have no Kürzel/Fahrten to manage, see AccountKind).
struct TeamMembersView: View {
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @State private var users: [User] = []

    private var userRepository: UserRepository { SwiftDataUserRepository(context: modelContext) }

    var body: some View {
        List {
            if users.isEmpty {
                Text("Keine Teammitglieder.").foregroundStyle(.secondary)
            }
            ForEach(users) { user in
                NavigationLink {
                    MemberDetailView(user: user, currentUser: currentUser) {
                        Task { await load() }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.name)
                            Text(user.abbreviation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if user.role == .admin {
                            Text("Admin")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else if user.role == .viceAdmin {
                            Text("Vice-Admin")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Mitglieder verwalten")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        let all = (try? await userRepository.allUsers(inGroup: groupID)) ?? []
        users = all.filter { $0.accountKind == .labTeam }
    }
}
