import Foundation
import SwiftData

/// An "Apotheke/Labor" from the Proben tab. Status is mock-only for now — see
/// BACKLOG #2 for the real reporting/interaction logic.
@Model
final class SampleLocation {
    var id: UUID = UUID()
    var groupID: UUID?
    var name: String = ""
    var address: String = ""
    var hasSamples: Bool = false
    var statusNote: String = ""
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        groupID: UUID?,
        name: String,
        address: String,
        hasSamples: Bool = false,
        statusNote: String = "",
        updatedAt: Date = .now
    ) {
        self.id = id
        self.groupID = groupID
        self.name = name
        self.address = address
        self.hasSamples = hasSamples
        self.statusNote = statusNote
        self.updatedAt = updatedAt
    }
}
