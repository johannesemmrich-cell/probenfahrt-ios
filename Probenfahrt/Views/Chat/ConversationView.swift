import SwiftUI

struct ConversationView: View {
    enum Mode {
        case group
        case direct(User)
    }

    let currentUser: User
    let mode: Mode
    let users: [User]

    @Environment(UnreadMessagesStore.self) private var unreadMessages

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var didInitialScroll = false
    @State private var sendHapticPulse = 0
    @State private var errorMessage: String?

    /// Caps how much history is kept in view state after a load — CloudKit
    /// itself has no Sortable index on `createdAt` (would need a manual
    /// CloudKit Dashboard change to query "last N" directly), so this only
    /// trims what SwiftUI has to render/diff, not the network fetch itself.
    private static let displayedMessageLimit = 100

    private let chatRepository: ChatRepository = CloudKitChatRepository()

    private var title: String {
        switch mode {
        case .group: return "Gruppen-Chat"
        case .direct(let partner): return partner.name
        }
    }

    private var conversationKey: String {
        switch mode {
        case .group: return UnreadMessagesStore.groupConversationKey
        case .direct(let partner): return partner.id.uuidString
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
                .onChange(of: messages.last?.id) {
                    // Keyed on the last message's id, not messages.count: once
                    // a conversation sits at the displayedMessageLimit cap,
                    // send() appends then trims back to the same count in one
                    // synchronous stretch, so count alone nets to no change
                    // and would silently stop triggering this at all.
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

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
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
        .sensoryFeedback(.impact(weight: .light), trigger: sendHapticPulse)
        .sensoryFeedback(.error, trigger: errorMessage) { _, newValue in newValue != nil }
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
        let fetched: [ChatMessage]?
        switch mode {
        case .group:
            fetched = try? await chatRepository.groupMessages(groupID: groupID)
        case .direct(let partner):
            fetched = try? await chatRepository.directMessages(groupID: groupID, between: currentUser.id, and: partner.id)
        }
        if let fetched {
            messages = Array(fetched.suffix(Self.displayedMessageLimit))
        }
        unreadMessages.markRead(conversationKey: conversationKey)
        await unreadMessages.refresh(currentUser: currentUser)
    }

    private func send() async {
        guard let groupID = currentUser.groupID else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        errorMessage = nil

        // Append locally right away instead of waiting on the CloudKit round
        // trip + a full history reload — the send below still happens, just
        // without blocking the bubble from appearing. Rolled back by id (not
        // "remove last") on failure, since further messages may have arrived
        // by the time the network call resolves.
        let recipientID: UUID? = { if case .direct(let partner) = mode { return partner.id }; return nil }()
        let optimisticMessage = ChatMessage(groupID: groupID, senderID: currentUser.id, recipientID: recipientID, text: text)
        messages.append(optimisticMessage)
        if messages.count > Self.displayedMessageLimit {
            messages.removeFirst(messages.count - Self.displayedMessageLimit)
        }
        sendHapticPulse += 1

        do {
            switch mode {
            case .group:
                try await chatRepository.sendGroupMessage(groupID: groupID, senderID: currentUser.id, text: text)
            case .direct(let partner):
                try await chatRepository.sendDirectMessage(groupID: groupID, senderID: currentUser.id, recipientID: partner.id, text: text)
            }
        } catch {
            messages.removeAll { $0.id == optimisticMessage.id }
            draft = text
            errorMessage = "Nachricht konnte nicht gesendet werden. Bitte erneut versuchen."
        }
    }
}
