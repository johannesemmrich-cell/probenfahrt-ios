import Foundation
import SwiftData

/// Named `TeamGroup`, not `Group` — `Group` collides with SwiftUI's own layout container type.
@Model
final class TeamGroup {
    var id: UUID = UUID()
    var name: String = ""
    var joinCode: String = ""
    /// Separate join code for self-service pharmacy/supplier accounts (see
    /// AccountKind.pharmacy) — resolves to the same group, but routes
    /// onboarding into the reduced Firmenname-only flow.
    var pharmacyJoinCode: String = ""
    var createdAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String,
        joinCode: String,
        pharmacyJoinCode: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.joinCode = joinCode
        self.pharmacyJoinCode = pharmacyJoinCode
        self.createdAt = createdAt
    }
}
