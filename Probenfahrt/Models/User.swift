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
    /// Optional password (hashed, see WebPasswordHashing) an admin can
    /// assign so this member can log into the web app (app.mediproben.com)
    /// without an Apple device — never the plaintext password itself.
    var webPasswordHash: String?

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
        webPasswordHash: String? = nil
    ) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.roleRawValue = role.rawValue
        self.accountKindRawValue = accountKind.rawValue
        self.groupID = groupID
        self.createdAt = createdAt
        self.webPasswordHash = webPasswordHash
    }
}
