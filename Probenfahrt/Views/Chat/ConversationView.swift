import SwiftUI
import SwiftData

struct ConversationView: View {
    enum Mode {
        case group
        case direct(User)
    }

    let currentUser: User
    let mode: Mode
    let users: [User]

    @Environment(\.modelContext) private var modelContext
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var didInitialScroll = false

    private var chatRepository: ChatRepository { SwiftDataChatRepository(context: modelContext) }

    private var title: String {
        switch mode {
        case .group: return "Gruppen-Chat"
        case .direct(let partner): return partner.name
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            messageBubble(message).id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    guard let lastID = messages.last?.id else { return }
                    // Don't force-scroll the initial historical load: when the
                    // content is shorter than the viewport, anchor:.bottom
                    // shifts the whole list upward past its natural position,
                    // hiding the top message behind the nav bar. Only scroll
                    // for messages added after that (i.e. just sent).
                    guard didInitialScroll else {
                        didInitialScroll = true
                        return
                    }
                    withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }

            Divider()

            HStack(alignment: .bottom) {
                TextField("Nachricht", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        let isMine = message.senderID == currentUser.id
        let senderName = users.first { $0.id == message.senderID }?.name ?? "?"

        VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
            if case .group = mode, !isMine {
                Text(senderName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(message.text)
                .padding(10)
                .background(isMine ? Color.accentColor : Color.gray.opacity(0.2))
                .foregroundStyle(isMine ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }

    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        switch mode {
        case .group:
            messages = (try? await chatRepository.groupMessages(groupID: groupID)) ?? []
        case .direct(let partner):
            messages = (try? await chatRepository.directMessages(groupID: groupID, between: currentUser.id, and: partner.id)) ?? []
        }
    }

    private func send() async {
        guard let groupID = currentUser.groupID else { return }
        let text = draft
        draft = ""
        switch mode {
        case .group:
            try? await chatRepository.sendGroupMessage(groupID: groupID, senderID: currentUser.id, text: text)
        case .direct(let partner):
            try? await chatRepository.sendDirectMessage(groupID: groupID, senderID: currentUser.id, recipientID: partner.id, text: text)
        }
        await load()
    }
}
