import XCTest

/// Regression guard: launches WITHOUT the reset flag, i.e. with the real
/// persistent SwiftData store exactly like a normal (non-test) first launch,
/// and checks the UI actually renders within a generous but bounded window.
/// A normal cold launch measured ~4s; 20s leaves headroom for CI/simulator
/// variance while still catching a genuine launch-blocking regression.
final class ColdLaunchUITests: XCTestCase {
    func testNormalColdLaunchRendersWithinBound() throws {
        let app = XCUIApplication()
        app.launch()

        let codeField = app.textFields["Beitrittscode"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 20))
    }
}
