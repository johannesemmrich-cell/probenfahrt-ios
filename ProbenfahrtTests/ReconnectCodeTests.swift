import Testing
import Foundation
@testable import Probenfahrt

struct ReconnectCodeTests {
    // MARK: - normalize

    @Test func acceptsThreeLettersAndLowercases() {
        #expect(ReconnectCode.normalize("ABC") == "abc")
        #expect(ReconnectCode.normalize("a1b") == "a1b")
        #expect(ReconnectCode.normalize("999") == "999")
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(ReconnectCode.normalize("  xy9 ") == "xy9")
    }

    @Test func rejectsWrongLength() {
        #expect(ReconnectCode.normalize("") == nil)
        #expect(ReconnectCode.normalize("ab") == nil)
        #expect(ReconnectCode.normalize("abcd") == nil)
    }

    @Test func rejectsNonAlphanumericCharacters() {
        #expect(ReconnectCode.normalize("a-b") == nil)
        #expect(ReconnectCode.normalize("a b") == nil)
        #expect(ReconnectCode.normalize("ab!") == nil)
        // Non-ASCII stays out so the code is always typeable on every
        // keyboard and matches CloudKit's exact-string comparison.
        #expect(ReconnectCode.normalize("äbc") == nil)
    }

    // MARK: - splitLoginInput

    @Test func splitsSimpleJoinCodeAndCode() {
        let parts = ReconnectCode.splitLoginInput("LABOR2026-JE1")
        #expect(parts?.joinCode == "LABOR2026")
        #expect(parts?.code == "je1")
    }

    @Test func splitsAtLastHyphenForHyphenatedJoinCodes() {
        let parts = ReconnectCode.splitLoginInput("apple-review-demo-X1Z")
        #expect(parts?.joinCode == "apple-review-demo")
        #expect(parts?.code == "x1z")
    }

    @Test func trimsWholeInput() {
        let parts = ReconnectCode.splitLoginInput("  LABOR2026-JE1 ")
        #expect(parts?.joinCode == "LABOR2026")
        #expect(parts?.code == "je1")
    }

    @Test func rejectsInputWithoutHyphen() {
        #expect(ReconnectCode.splitLoginInput("LABOR2026") == nil)
    }

    @Test func rejectsEmptyJoinCodePart() {
        #expect(ReconnectCode.splitLoginInput("-abc") == nil)
    }

    @Test func rejectsInvalidCodePart() {
        #expect(ReconnectCode.splitLoginInput("LABOR2026-") == nil)
        #expect(ReconnectCode.splitLoginInput("LABOR2026-ab") == nil)
        #expect(ReconnectCode.splitLoginInput("LABOR2026-abcd") == nil)
    }
}
