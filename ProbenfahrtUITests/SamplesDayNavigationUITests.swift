import XCTest

/// Demonstrates the day-based Proben reporting end to end using the seeded
/// demo data (3 locations with samples "today", 3 without, none for any
/// other day): a fresh lab-team member sees today's reports in the "Proben"
/// tab, and browsing to the previous day shows an empty list since no
/// report exists for that day.
final class SamplesDayNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTodaysReportsShowUpAndPastDayIsEmpty() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITest_ResetState"]
        app.launch()

        let joinCodeField = app.textFields["Beitrittscode"]
        XCTAssertTrue(joinCodeField.waitForExistence(timeout: 5))
        joinCodeField.tap()
        joinCodeField.typeText("LABOR2026")
        app.buttons["Weiter"].tap()

        let nameField = app.textFields["Vollständiger Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Test Nutzer")
        app.textFields["Kürzel (z.B. JE)"].tap()
        app.textFields["Kürzel (z.B. JE)"].typeText("TN")
        app.buttons["Beitreten"].tap()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Proben"].tap()

        XCTAssertTrue(app.staticTexts["Proben vorhanden (3)"].waitForExistence(timeout: 5))
        snap(app, "day-nav-1-today-with-samples")

        app.buttons["Vorheriger Tag"].tap()
        XCTAssertTrue(app.staticTexts["Keine Meldungen an diesem Tag"].waitForExistence(timeout: 5))
        snap(app, "day-nav-2-yesterday-empty")

        app.buttons["Heute"].tap()
        XCTAssertTrue(app.staticTexts["Proben vorhanden (3)"].waitForExistence(timeout: 5))
        snap(app, "day-nav-3-back-to-today")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        attachment.name = name
        add(attachment)
    }
}
