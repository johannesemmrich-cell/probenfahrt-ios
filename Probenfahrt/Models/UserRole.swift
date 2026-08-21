import Foundation

enum UserRole: String, Codable, CaseIterable {
    /// Haupt-Admin — full rights, incl. removing members, changing anyone's
    /// Kürzel, and promoting/demoting Vice-Admins.
    case admin
    /// Promoted by a Haupt-Admin (see MemberDetailView) — most admin rights,
    /// except removing members, changing Kürzel, or promoting others.
    case viceAdmin
    case member
}
