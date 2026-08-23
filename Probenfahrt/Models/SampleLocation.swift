import Foundation
import SwiftData

/// An "Apotheke/Labor" identity for the Proben tab — name/address plus which
/// group it belongs to. The actual yes/no status per day lives in
/// SampleReport, not here (see BACKLOG #3 for the QR-code-only reporting
/// path this identity will also need to support).
@Model
final class SampleLocation {
    var id: UUID = UUID()
    var groupID: UUID?
    var name: String = ""
    var address: String = ""
    /// Set for locations self-managed by a pharmacy account (see
    /// AccountKind.pharmacy) via PharmacySamplesView; nil for the legacy
    /// seeded/admin-only demo locations.
    var ownerUserID: UUID?

    init(
        id: UUID = UUID(),
        groupID: UUID?,
        name: String,
        address: String,
        ownerUserID: UUID? = nil
    ) {
        self.id = id
        self.groupID = groupID
        self.name = name
        self.address = address
        self.ownerUserID = ownerUserID
    }
}
