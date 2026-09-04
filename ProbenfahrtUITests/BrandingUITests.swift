import XCTest

/// Ad-hoc visual check for the partner branding (logo mark + yellow accent)
/// added to onboarding, "Über Probenfahrt", and the calendar's today
/// highlight. Not a strict regression test — just screenshots to eyeball.
final class BrandingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBrandingShowsUpAcrossScreens() throws {
        // Wie PastSamplesUITests: Onboarding löst den Beitrittscode jetzt über
        // CloudKitUserRepository (BACKLOG #1) statt lokalem SwiftData auf —
        // ohne signiertes iCloud-Testkonto im UI-Test-Simulator kommt die App
        // über den Code-Schritt gar nicht mehr hinaus.
        throw XCTSkip("Onboarding löst den Beitrittscode jetzt über CloudKit auf — braucht ein signiertes iCloud-Testkonto, siehe CloudKitUserRepository.")

        let app = XCUIApplication()
        app.launchArguments += ["-UITest_ResetState"]
        app.launch()

        let joinCodeField = app.textFields["Beitrittscode"]
        XCTAssertTrue(joinCodeField.waitForExistence(timeout: 5))
        snap(app, "brand-1-onboarding-code-step")

        joinCodeField.tap()
        joinCodeField.typeText("LABOR2026")
        snap(app, "brand-1b-onboarding-code-step-enabled-button")
        app.buttons["Weiter"].tap()

        let nameField = app.textFields["Vollständiger Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        snap(app, "brand-2-onboarding-identity-step")
        nameField.tap()
        nameField.typeText("Test Nutzer")
        app.textFields["Kürzel (z.B. JE)"].tap()
        app.textFields["Kürzel (z.B. JE)"].typeText("TN")
        snap(app, "brand-2b-onboarding-identity-step-enabled-button")
        app.buttons["Beitreten"].tap()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        tabBar.buttons["Kalender"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        snap(app, "brand-3-calendar-today-highlight")

        tabBar.buttons["Einstellungen"].tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        app.staticTexts["Über Probenfahrt"].tap()
        XCTAssertTrue(app.navigationBars["Über"].waitForExistence(timeout: 5))
        snap(app, "brand-4-about-screen")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        attachment.name = name
        add(attachment)
    }
}
