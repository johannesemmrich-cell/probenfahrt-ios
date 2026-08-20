import Foundation
import SwiftData

@Model
final class User {
    var id: UUID = UUID()
    var name: String = ""
    var abbreviation: String = ""
    var roleRawValue: String = UserRole.member.rawValue
    var groupID: UUID?
    var createdAt: Date = Date.now

    var role: UserRole {
        get { UserRole(rawValue: roleRawValue) ?? .member }
        set { roleRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        abbreviation: String,
        role: UserRole = .member,
        groupID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.roleRawValue = role.rawValue
        self.groupID = groupID
        self.createdAt = createdAt
    }
}
