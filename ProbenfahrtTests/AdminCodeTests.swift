import Testing
@testable import Probenfahrt

struct AdminCodeTests {
    @Test func matchesExactCode() {
        #expect(AdminCode.matches(AdminCode.value))
    }

    @Test func matchesCaseInsensitively() {
        #expect(AdminCode.matches(AdminCode.value.lowercased()))
        #expect(AdminCode.matches(AdminCode.value.uppercased()))
    }

    @Test func matchesWithSurroundingWhitespace() {
        #expect(AdminCode.matches("  \(AdminCode.value)  "))
    }

    @Test func rejectsWrongCode() {
        #expect(!AdminCode.matches("Vice-Admin"))
        #expect(!AdminCode.matches("\(AdminCode.value)1"))
        #expect(!AdminCode.matches(String(AdminCode.value.dropLast())))
    }

    @Test func rejectsEmptyInput() {
        #expect(!AdminCode.matches(""))
        #expect(!AdminCode.matches("   "))
    }
}
