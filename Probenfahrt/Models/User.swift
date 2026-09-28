import Foundation
import SwiftData

@Model
final class User {
    var id: UUID = UUID()
    var name: String = ""
    var abbreviation: String = ""
    var roleRawValue: String = UserRole.member.rawValue
    var accountKindRawValue: String = AccountKind.labTeam.rawValue
    var groupID: UUID?
    var createdAt: Date = Date.now
    /// Optional password (encrypted, see WebPasswordEncryption) an admin can
    /// assign so this member can log into the web app (app.mediproben.com)
    /// without an Apple device. Reversible (not a one-way hash) so an admin
    /// can view it again in MemberDetailView.
    var webPasswordEncrypted: String?
    /// Set by `deleteUser` (soft delete) when an admin removes this member
    /// from the group. The record itself is kept so past `SurveyEntry`
    /// rows can still resolve a name/abbreviation instead of silently
    /// disappearing from day details, "Vergangene Umfragen" and the PDF
    /// Monatsauswertung. `allUsers` filters these out everywhere an active
    /// roster is needed (onboarding, admin counts, Kürzel-Eindeutigkeit),
    /// so the name/Kürzel become free for reuse; `allUsersIncludingRemoved`
    /// is the escape hatch for historical name resolution.
    var isRemoved: Bool = false

    var role: UserRole {
        get { UserRole(rawValue: roleRawValue) ?? .member }
        set { roleRawValue = newValue.rawValue }
    }

    var accountKind: AccountKind {
        get { AccountKind(rawValue: accountKindRawValue) ?? .labTeam }
        set { accountKindRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        abbreviation: String,
        role: UserRole = .member,
        accountKind: AccountKind = .labTeam,
        groupID: UUID? = nil,
        createdAt: Date = .now,
        webPasswordEncrypted: String? = nil,
        isRemoved: Bool = false
    ) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.roleRawValue = role.rawValue
        self.accountKindRawValue = accountKind.rawValue
        self.groupID = groupID
        self.createdAt = createdAt
        self.webPasswordEncrypted = webPasswordEncrypted
        self.isRemoved = isRemoved
    }
}
