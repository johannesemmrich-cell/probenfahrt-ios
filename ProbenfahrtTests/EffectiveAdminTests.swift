import Testing
import Foundation
@testable import Probenfahrt

@MainActor
struct EffectiveAdminTests {
    private let calendar = Calendar.current

    private func makeUser(role: UserRole) -> User {
        User(name: "Test Nutzer", abbreviation: "TN", role: role)
    }

    /// `AdminPreviewStore`/`DevModeStore` persist to shared
    /// `UserDefaults.standard` — on a device/simulator where the real app
    /// (or a UI test) has also run, their on-disk values can leak in. Force
    /// the deterministic values these tests need instead of trusting
    /// whatever ended up on disk.
    private func adminPreview(enabled: Bool = false) -> AdminPreviewStore {
        let store = AdminPreviewStore()
        store.isEnabled = enabled
        return store
    }

    private func devMode(adminPreviewActive: Bool = false) -> DevModeStore {
        let store = DevModeStore()
        store.isAdminPreviewActive = adminPreviewActive
        return store
    }

    // MARK: — isEffectiveAdmin / isFullAdmin

    @Test func memberIsNeitherEffectiveNorFullAdmin() {
        let member = makeUser(role: .member)
        #expect(!isEffectiveAdmin(user: member, adminPreview: adminPreview(), devMode: devMode()))
        #expect(!isFullAdmin(user: member, adminPreview: adminPreview(), devMode: devMode()))
    }

    @Test func viceAdminIsEffectiveButNotFullAdmin() {
        let viceAdmin = makeUser(role: .viceAdmin)
        #expect(isEffectiveAdmin(user: viceAdmin, adminPreview: adminPreview(), devMode: devMode()))
        #expect(!isFullAdmin(user: viceAdmin, adminPreview: adminPreview(), devMode: devMode()))
    }

    @Test func hauptAdminIsBothEffectiveAndFullAdmin() {
        let admin = makeUser(role: .admin)
        #expect(isEffectiveAdmin(user: admin, adminPreview: adminPreview(), devMode: devMode()))
        #expect(isFullAdmin(user: admin, adminPreview: adminPreview(), devMode: devMode()))
    }

    @Test func adminPreviewOverrideGrantsFullAdminToMember() {
        let member = makeUser(role: .member)
        #expect(isFullAdmin(user: member, adminPreview: adminPreview(enabled: true), devMode: devMode()))
    }

    @Test func devModeAdminPreviewOverrideGrantsFullAdminToMember() {
        let member = makeUser(role: .member)
        #expect(isFullAdmin(user: member, adminPreview: adminPreview(), devMode: devMode(adminPreviewActive: true)))
    }

    // MARK: — isDeveloperOverride

    @Test func noOverrideIsNotDeveloperOverride() {
        #expect(!isDeveloperOverride(adminPreview: adminPreview(), devMode: devMode()))
    }

    @Test func adminPreviewEnabledIsDeveloperOverride() {
        #expect(isDeveloperOverride(adminPreview: adminPreview(enabled: true), devMode: devMode()))
    }

    @Test func devModeAdminPreviewActiveIsDeveloperOverride() {
        #expect(isDeveloperOverride(adminPreview: adminPreview(), devMode: devMode(adminPreviewActive: true)))
    }

    /// A real Haupt-Admin role alone doesn't count — `isDeveloperOverride`
    /// only reflects the two dev/preview flags, not the user's actual role.
    @Test func realHauptAdminAloneIsNotDeveloperOverride() {
        #expect(!isDeveloperOverride(adminPreview: adminPreview(), devMode: devMode()))
    }

    // MARK: — canEditSurveyDay

    @Test func memberCanEditFutureDay() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        let day = SurveyDay(date: tomorrow, groupID: nil)
        let member = makeUser(role: .member)
        #expect(canEditSurveyDay(day, user: member, adminPreview: adminPreview(), devMode: devMode(), calendar: calendar))
    }

    @Test func memberCannotEditPastDay() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        let day = SurveyDay(date: yesterday, groupID: nil)
        let member = makeUser(role: .member)
        #expect(!canEditSurveyDay(day, user: member, adminPreview: adminPreview(), devMode: devMode(), calendar: calendar))
    }

    @Test func memberCanEditToday() {
        let day = SurveyDay(date: .now, groupID: nil)
        let member = makeUser(role: .member)
        #expect(canEditSurveyDay(day, user: member, adminPreview: adminPreview(), devMode: devMode(), calendar: calendar))
    }

    @Test func hauptAdminCanEditPastDay() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        let day = SurveyDay(date: yesterday, groupID: nil)
        let admin = makeUser(role: .admin)
        #expect(canEditSurveyDay(day, user: admin, adminPreview: adminPreview(), devMode: devMode(), calendar: calendar))
    }

    @Test func viceAdminCanEditPastDay() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        let day = SurveyDay(date: yesterday, groupID: nil)
        let viceAdmin = makeUser(role: .viceAdmin)
        #expect(canEditSurveyDay(day, user: viceAdmin, adminPreview: adminPreview(), devMode: devMode(), calendar: calendar))
    }

    // MARK: — shouldShowQuickToggle

    @Test func memberSeesQuickToggleOnFutureDay() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        let day = SurveyDay(date: tomorrow, groupID: nil)
        let member = makeUser(role: .member)
        #expect(shouldShowQuickToggle(for: day, user: member, adminPreview: adminPreview(), devMode: devMode(), calendar: calendar))
    }

    @Test func memberNeverSeesQuickToggleOnPastDay() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        let day = SurveyDay(date: yesterday, groupID: nil)
        let member = makeUser(role: .member)
        #expect(!shouldShowQuickToggle(for: day, user: member, adminPreview: adminPreview(), devMode: devMode(), calendar: calendar))
    }

    @Test func hauptAdminSeesQuickToggleOnFutureDay() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        let day = SurveyDay(date: tomorrow, groupID: nil)
        let admin = makeUser(role: .admin)
        #expect(shouldShowQuickToggle(for: day, user: admin, adminPreview: adminPreview(), devMode: devMode(), calendar: calendar))
    }

    @Test func hauptAdminDoesNotSeeQuickToggleOnPastDay() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        let day = SurveyDay(date: yesterday, groupID: nil)
        let admin = makeUser(role: .admin)
        #expect(!shouldShowQuickToggle(for: day, user: admin, adminPreview: adminPreview(), devMode: devMode(), calendar: calendar))
    }

    @Test func viceAdminDoesNotSeeQuickToggleOnPastDay() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        let day = SurveyDay(date: yesterday, groupID: nil)
        let viceAdmin = makeUser(role: .viceAdmin)
        #expect(!shouldShowQuickToggle(for: day, user: viceAdmin, adminPreview: adminPreview(), devMode: devMode(), calendar: calendar))
    }

    @Test func hauptAdminSeesQuickToggleOnToday() {
        let day = SurveyDay(date: .now, groupID: nil)
        let admin = makeUser(role: .admin)
        #expect(shouldShowQuickToggle(for: day, user: admin, adminPreview: adminPreview(), devMode: devMode(), calendar: calendar))
    }
}
