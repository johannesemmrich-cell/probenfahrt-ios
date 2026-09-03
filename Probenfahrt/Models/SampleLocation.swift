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
    /// Unique, unguessable-enough token embedded in the QR-code web link
    /// (see BACKLOG #3) so a pharmacy without the app can report today's
    /// status from a plain webpage — the only thing that identifies which
    /// location a web check-in belongs to, since there's no account.
    var token: String = UUID().uuidString
    /// True for pharmacies meant to scan their own QR code and self-report
    /// via the web check-in; false for ones the admin reports on behalf of
    /// (e.g. a pharmacy that struggles with the web check-in and just calls
    /// in instead) — those don't need a QR code shown/handed out at all.
    var usesQRCheckIn: Bool = true

    init(
        id: UUID = UUID(),
        groupID: UUID?,
        name: String,
        address: String,
        ownerUserID: UUID? = nil,
        token: String = UUID().uuidString,
        usesQRCheckIn: Bool = true
    ) {
        self.id = id
        self.groupID = groupID
        self.name = name
        self.address = address
        self.ownerUserID = ownerUserID
        self.token = token
        self.usesQRCheckIn = usesQRCheckIn
    }
}
