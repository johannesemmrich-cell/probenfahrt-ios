import XCTest

/// Covers the two alternate onboarding paths from the join-code step:
/// the pharmacy/Apotheken flow (reduced 2-tab app) and the Dev-Mode
/// password bypass (straight into the standard app with Dev Mode active).
final class PharmacyOnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPharmacyCodeLeadsToReducedTwoTabApp() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITest_ResetState"]
        app.launch()

        let codeField = app.textFields["Beitrittscode"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 5))
        codeField.tap()
        codeField.typeText("PROBEN2026")
        app.buttons["Weiter"].tap()

        let firmField = app.textFields["Apotheken-/Firmenname"]
        XCTAssertTrue(firmField.waitForExistence(timeout: 5))
        firmField.tap()
        firmField.typeText("Apotheke Test")
        app.buttons["Beitreten"].tap()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["Proben"].exists)
        XCTAssertTrue(tabBar.buttons["Einstellungen"].exists)
        XCTAssertFalse(tabBar.buttons["Umfragen"].exists)
        XCTAssertFalse(tabBar.buttons["Kalender"].exists)
        XCTAssertFalse(tabBar.buttons["Chat"].exists)

        XCTAssertTrue(app.staticTexts["Habt ihr heute Proben?"].waitForExistence(timeout: 5))
        snap(app, "pharmacy-1-proben")

        app.buttons["Ja, wir haben Proben"].tap()
        XCTAssertTrue(app.staticTexts["Aktueller Status: Proben vorhanden"].waitForExistence(timeout: 5))
        snap(app, "pharmacy-2-proben-ja")

        tabBar.buttons["Einstellungen"].tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Firmenname"].waitForExistence(timeout: 5))
        let firmNameValue = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Apotheke Test")).firstMatch
        XCTAssertTrue(firmNameValue.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Admin"].exists)
        snap(app, "pharmacy-3-einstellungen")
    }

    func testDevPasswordInCodeFieldBypassesStraightIntoStandardApp() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITest_ResetState"]
        app.launch()

        let codeField = app.textFields["Beitrittscode"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 5))
        codeField.tap()
        codeField.typeText("Isg#45krusgL.")
        app.buttons["Weiter"].tap()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["Umfragen"].exists)
        XCTAssertTrue(tabBar.buttons["Kalender"].exists)
        XCTAssertTrue(tabBar.buttons["Proben"].exists)
        XCTAssertTrue(tabBar.buttons["Chat"].exists)
        XCTAssertTrue(tabBar.buttons["Einstellungen"].exists)

        tabBar.buttons["Einstellungen"].tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["DEV"].waitForExistence(timeout: 5))
        snap(app, "devbypass-einstellungen")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        attachment.name = name
        add(attachment)
    }
}
