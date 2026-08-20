import Foundation
import SwiftData

/// `recipientID == nil` → group-channel message; `recipientID` set → 1:1 DM.
/// A DM thread is derived by querying on the (sender, recipient) pair, so there's
/// no separate "conversation" record that could get duplicated.
@Model
final class ChatMessage {
    var id: UUID = UUID()
    var groupID: UUID?
    var senderID: UUID?
    var recipientID: UUID?
    var text: String = ""
    var createdAt: Date = Date.now

    init(
        id: UUID = UUID(),
        groupID: UUID?,
        senderID: UUID?,
        recipientID: UUID? = nil,
        text: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.groupID = groupID
        self.senderID = senderID
        self.recipientID = recipientID
        self.text = text
        self.createdAt = createdAt
    }
}
