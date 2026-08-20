import SwiftUI
import SwiftData

struct ChatView: View {
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @State private var users: [User] = []

    private var userRepository: UserRepository { SwiftDataUserRepository(context: modelContext) }

    private var otherUsers: [User] {
        users.filter { $0.id != currentUser.id }.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ConversationView(currentUser: currentUser, mode: .group, users: users)
                    } label: {
                        Label("Gruppen-Chat", systemImage: "person.3.fill")
                    }
                }

                Section("Direktnachrichten") {
                    ForEach(otherUsers) { partner in
                        NavigationLink {
                            ConversationView(currentUser: currentUser, mode: .direct(partner), users: users)
                        } label: {
                            Text(partner.name)
                        }
                    }
                }
            }
            .navigationTitle("Chat")
            .task { await load() }
        }
    }

    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        users = (try? await userRepository.allUsers(inGroup: groupID)) ?? []
    }
}
