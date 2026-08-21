import XCTest

/// Drives the actual golden path end to end: onboarding (name/Kürzel + join
/// code) through all 5 tabs. Launched with a reset flag so every run starts
/// from a clean, freshly-seeded state regardless of prior runs.
final class OnboardingAndTabsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingThenAllTabsReachable() throws {
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

        let abbreviationField = app.textFields["Kürzel (z.B. JE)"]
        abbreviationField.tap()
        abbreviationField.typeText("TN")

        app.buttons["Beitreten"].tap()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["Umfragen"].exists)
        XCTAssertTrue(tabBar.buttons["Kalender"].exists)
        XCTAssertTrue(tabBar.buttons["Proben"].exists)
        XCTAssertTrue(tabBar.buttons["Chat"].exists)
        XCTAssertTrue(tabBar.buttons["Einstellungen"].exists)

        XCTAssertTrue(app.navigationBars["Umfragen"].waitForExistence(timeout: 5))
        snap(app, "1-umfragen")

        tabBar.buttons["Kalender"].tap()
        XCTAssertTrue(app.navigationBars["Kalender"].waitForExistence(timeout: 5))
        snap(app, "2-kalender")

        tabBar.buttons["Proben"].tap()
        XCTAssertTrue(app.navigationBars["Proben"].waitForExistence(timeout: 5))

        snap(app, "3-proben")

        tabBar.buttons["Chat"].tap()
        XCTAssertTrue(app.navigationBars["Chat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Gruppen-Chat"].waitForExistence(timeout: 5))
        app.staticTexts["Gruppen-Chat"].tap()
        sleep(1)
        snap(app, "4-chat")
        app.navigationBars.buttons.firstMatch.tap()

        tabBar.buttons["Einstellungen"].tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))

        // Dev admin-preview toggle should reveal the admin-only report link.
        let adminToggle = app.switches["Als Admin anzeigen"]
        XCTAssertTrue(adminToggle.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Monatsauswertung (PDF)"].exists)

        // Plain .tap() taps the center of the reported accessibility frame,
        // which misses the actual switch control on this full-width Form row;
        // bias toward the switch's visual position (right edge) instead.
        adminToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(adminToggle.value as? String, "1")
        XCTAssertTrue(app.staticTexts["Monatsauswertung (PDF)"].waitForExistence(timeout: 5))
        snap(app, "5-einstellungen")

        // Über/Datenschutz + Emmrich-Banner sitzen unten, außerhalb des ersten Screens.
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Über Probenfahrt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Datenschutz"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Emmrich Apps"].waitForExistence(timeout: 5))
        snap(app, "6-einstellungen-unten")

        app.staticTexts["Über Probenfahrt"].tap()
        XCTAssertTrue(app.navigationBars["Über"].waitForExistence(timeout: 5))
        snap(app, "7-ueber")
        app.navigationBars.buttons.firstMatch.tap()

        app.staticTexts["Datenschutz"].tap()
        XCTAssertTrue(app.navigationBars["Datenschutz"].waitForExistence(timeout: 5))
        snap(app, "8-datenschutz")
        app.navigationBars.buttons.firstMatch.tap()

        tabBar.buttons["Umfragen"].tap()
        XCTAssertTrue(app.navigationBars["Umfragen"].waitForExistence(timeout: 5))

        // Vergangene Umfragen render as the same "Fahrplan vom...bis..."
        // week blocks as the 2 aktuell blocks, just further back.
        app.buttons["Vergangen"].tap()
        XCTAssertTrue(app.navigationBars["Vergangene Umfragen"].waitForExistence(timeout: 5))
        let fahrplanHeader = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Fahrplan vom")).firstMatch
        XCTAssertTrue(fahrplanHeader.waitForExistence(timeout: 5))
        snap(app, "9-vergangene-umfragen")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        attachment.name = name
        add(attachment)
    }
}
