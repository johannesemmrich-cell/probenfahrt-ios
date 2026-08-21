import Foundation

/// Distinguishes a regular lab-team member from a self-service pharmacy/
/// supplier account (onboarded via the separate PROBEN2026 code), which gets
/// a reduced 2-tab app (Proben + Einstellungen) instead of the full 5 tabs.
enum AccountKind: String, Codable, CaseIterable {
    case labTeam
    case pharmacy
}
