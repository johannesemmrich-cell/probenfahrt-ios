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
    /// Optional password an admin can assign so this member can identify
    /// themselves on the web check-in (mediproben.com) without the app —
    /// plaintext, same deliberately-simple security posture as the group's
    /// Admin-Code (see README "Test-Zugänge"), not a real auth system.
    var webPassword: String?

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
        webPassword: String? = nil
    ) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.roleRawValue = role.rawValue
        self.accountKindRawValue = accountKind.rawValue
        self.groupID = groupID
        self.createdAt = createdAt
        self.webPassword = webPassword
    }
}
