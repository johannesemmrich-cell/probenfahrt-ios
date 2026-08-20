import Foundation
import SwiftData

/// Named `TeamGroup`, not `Group` — `Group` collides with SwiftUI's own layout container type.
@Model
final class TeamGroup {
    var id: UUID = UUID()
    var name: String = ""
    var joinCode: String = ""
    var createdAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String,
        joinCode: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.joinCode = joinCode
        self.createdAt = createdAt
    }
}
