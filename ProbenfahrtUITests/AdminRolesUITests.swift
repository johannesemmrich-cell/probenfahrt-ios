import XCTest

/// Covers the new Haupt-Admin self-unlock (Admin-Code field at the bottom of
/// Einstellungen) and the Vice-Admin promotion toggle in Mitglieder
/// verwalten.
final class AdminRolesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAdminCodeUnlocksHauptAdminAndPromotesViceAdmin() throws {
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
        tabBar.buttons["Einstellungen"].tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))

        // A fresh member is not yet Haupt-Admin — the Admin section shouldn't exist yet.
        XCTAssertFalse(app.staticTexts["Mitglieder verwalten"].exists)

        app.swipeUp()
        app.swipeUp()
        let codeField = app.textFields["Code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 5))
        codeField.tap()
        codeField.typeText("Admin")
        app.buttons["Bestätigen"].tap()

        // Promotion is real/persisted (not just a preview) — Admin section appears.
        XCTAssertTrue(app.staticTexts["Mitglieder verwalten"].waitForExistence(timeout: 5))
        snap(app, "10-haupt-admin-freigeschaltet")

        app.staticTexts["Mitglieder verwalten"].tap()
        XCTAssertTrue(app.navigationBars["Mitglieder verwalten"].waitForExistence(timeout: 5))

        // Pick a different seeded member (not "Test Nutzer" itself) to promote to Vice-Admin.
        let annaRow = app.staticTexts["Anna Weber"]
        XCTAssertTrue(annaRow.waitForExistence(timeout: 5))
        annaRow.tap()

        XCTAssertTrue(app.navigationBars["Anna Weber"].waitForExistence(timeout: 5))
        let viceAdminToggle = app.switches["Vice-Admin"]
        XCTAssertTrue(viceAdminToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(viceAdminToggle.value as? String, "0")
        snap(app, "11-member-detail-vor-befoerderung")

        viceAdminToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(viceAdminToggle.value as? String, "1")
        snap(app, "12-member-detail-vice-admin")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Vice-Admin"].waitForExistence(timeout: 5))
        snap(app, "13-mitgliederliste-mit-vice-admin-badge")
    }

    /// Even a real Haupt-Admin can't remove the group's last admin or strip
    /// an existing Haupt-Admin's role — only the DevMode "Alle Admin-Rechte"
    /// override can, as a deliberate escape hatch.
    func testDevModeAdminPreviewCanRemoveLastHauptAdmin() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITest_ResetState"]
        app.launch()

        // Dev-password bypass: straight into the standard app, Dev Mode already active.
        let codeField = app.textFields["Beitrittscode"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 5))
        codeField.tap()
        codeField.typeText("Isg#45krusgL.")
        app.buttons["Weiter"].tap()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        tabBar.buttons["Einstellungen"].tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        app.swipeUp()

        let developerModeLink = app.staticTexts["Entwicklermodus"]
        XCTAssertTrue(developerModeLink.waitForExistence(timeout: 5))
        developerModeLink.tap()
        XCTAssertTrue(app.navigationBars["Entwicklermodus"].waitForExistence(timeout: 5))

        let adminPreviewToggle = app.switches["Alle Admin-Rechte (Haupt-Admin)"]
        XCTAssertTrue(adminPreviewToggle.waitForExistence(timeout: 5))
        adminPreviewToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(adminPreviewToggle.value as? String, "1")
        snap(app, "14-devmode-admin-vorschau-an")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))

        let membersLink = app.staticTexts["Mitglieder verwalten"]
        XCTAssertTrue(membersLink.waitForExistence(timeout: 5))
        membersLink.tap()
        XCTAssertTrue(app.navigationBars["Mitglieder verwalten"].waitForExistence(timeout: 5))

        // Promote a regular member straight to Haupt-Admin — a real Haupt-Admin
        // can only offer Vice-Admin; only the Dev-Mode/Admin-Vorschau override
        // can appoint a peer Haupt-Admin outright.
        let annaRow = app.staticTexts["Anna Weber"]
        XCTAssertTrue(annaRow.waitForExistence(timeout: 5))
        annaRow.tap()
        XCTAssertTrue(app.navigationBars["Anna Weber"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.swipeUp()

        let promoteButton = app.buttons["Zum Haupt-Admin machen"]
        XCTAssertTrue(promoteButton.waitForExistence(timeout: 5))
        promoteButton.tap()
        XCTAssertTrue(app.staticTexts["Rolle, Haupt-Admin"].waitForExistence(timeout: 5))
        snap(app, "17-anna-zum-haupt-admin-befoerdert")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Mitglieder verwalten"].waitForExistence(timeout: 5))

        // "Johannes Emmrich" is the sole seeded Haupt-Admin.
        let johannesRow = app.staticTexts["Johannes Emmrich"]
        XCTAssertTrue(johannesRow.waitForExistence(timeout: 5))
        johannesRow.tap()
        XCTAssertTrue(app.navigationBars["Johannes Emmrich"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.swipeUp()

        let removeAdminStatusButton = app.buttons["Haupt-Admin-Status entfernen"]
        XCTAssertTrue(removeAdminStatusButton.waitForExistence(timeout: 5))
        snap(app, "15-haupt-admin-status-entfernen-sichtbar")

        let removeFromGroupButton = app.buttons["Aus Gruppe entfernen"]
        XCTAssertTrue(removeFromGroupButton.waitForExistence(timeout: 5))
        removeFromGroupButton.tap()
        app.buttons["Entfernen"].tap()

        // Bypassed the last-admin guard — no error, back on the (now-shorter) roster.
        XCTAssertTrue(app.navigationBars["Mitglieder verwalten"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Johannes Emmrich"].exists)
        snap(app, "16-letzter-admin-entfernt")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        attachment.name = name
        add(attachment)
    }
}
