import Testing
import Foundation
@testable import Probenfahrt

@MainActor
struct CanRemoveUserTests {
    private func makeUser(role: UserRole) -> User {
        User(name: "Test Nutzer", abbreviation: "TN", role: role)
    }

    @Test func memberCanAlwaysBeRemoved() {
        let member = makeUser(role: .member)
        #expect(canRemoveUser(member, adminCountInGroup: 0))
        #expect(canRemoveUser(member, adminCountInGroup: 1))
    }

    @Test func adminCanBeRemovedWhenAnotherAdminExists() {
        let admin = makeUser(role: .admin)
        #expect(canRemoveUser(admin, adminCountInGroup: 2))
    }

    @Test func lastAdminCannotBeRemoved() {
        let admin = makeUser(role: .admin)
        #expect(!canRemoveUser(admin, adminCountInGroup: 1))
    }
}
