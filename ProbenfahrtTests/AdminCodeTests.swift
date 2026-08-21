import Testing
@testable import Probenfahrt

struct AdminCodeTests {
    @Test func matchesExactCode() {
        #expect(AdminCode.matches("Admin"))
    }

    @Test func matchesCaseInsensitively() {
        #expect(AdminCode.matches("admin"))
        #expect(AdminCode.matches("ADMIN"))
    }

    @Test func matchesWithSurroundingWhitespace() {
        #expect(AdminCode.matches("  Admin  "))
    }

    @Test func rejectsWrongCode() {
        #expect(!AdminCode.matches("Vice-Admin"))
        #expect(!AdminCode.matches("Admin1"))
    }

    @Test func rejectsEmptyInput() {
        #expect(!AdminCode.matches(""))
        #expect(!AdminCode.matches("   "))
    }
}
