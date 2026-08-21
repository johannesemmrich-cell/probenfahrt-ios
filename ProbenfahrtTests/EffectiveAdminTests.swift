import Testing
import Foundation
@testable import Probenfahrt

@MainActor
struct EffectiveAdminTests {
    private let calendar = Calendar.current

    private func makeUser(role: UserRole) -> User {
        User(name: "Test Nutzer", abbreviation: "TN", role: role)
    }

    /// `AdminPreviewStore` persists to shared `UserDefaults.standard` — on a
    /// device/simulator where the real app (or a UI test) has also run, its
    /// on-disk value can leak in. Force the deterministic value these tests
    /// need instead of trusting whatever ended up on disk.
    private func adminPreview(enabled: Bool) -> AdminPreviewStore {
        let store = AdminPreviewStore()
        store.isEnabled = enabled
        return store
    }

    @Test func memberCanEditFutureDay() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        let day = SurveyDay(date: tomorrow, groupID: nil)
        let member = makeUser(role: .member)
        #expect(canEditSurveyDay(day, user: member, adminPreview: adminPreview(enabled: false), calendar: calendar))
    }

    @Test func memberCannotEditPastDay() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        let day = SurveyDay(date: yesterday, groupID: nil)
        let member = makeUser(role: .member)
        #expect(!canEditSurveyDay(day, user: member, adminPreview: adminPreview(enabled: false), calendar: calendar))
    }

    @Test func memberCanEditToday() {
        let day = SurveyDay(date: .now, groupID: nil)
        let member = makeUser(role: .member)
        #expect(canEditSurveyDay(day, user: member, adminPreview: adminPreview(enabled: false), calendar: calendar))
    }

    @Test func adminCanEditPastDay() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        let day = SurveyDay(date: yesterday, groupID: nil)
        let admin = makeUser(role: .admin)
        #expect(canEditSurveyDay(day, user: admin, adminPreview: adminPreview(enabled: false), calendar: calendar))
    }

    // MARK: — shouldShowQuickToggle

    @Test func memberSeesQuickToggleOnFutureDay() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        let day = SurveyDay(date: tomorrow, groupID: nil)
        let member = makeUser(role: .member)
        #expect(shouldShowQuickToggle(for: day, user: member, adminPreview: adminPreview(enabled: false), calendar: calendar))
    }

    @Test func memberNeverSeesQuickToggleOnPastDay() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        let day = SurveyDay(date: yesterday, groupID: nil)
        let member = makeUser(role: .member)
        #expect(!shouldShowQuickToggle(for: day, user: member, adminPreview: adminPreview(enabled: false), calendar: calendar))
    }

    @Test func adminSeesQuickToggleOnFutureDay() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now)!
        let day = SurveyDay(date: tomorrow, groupID: nil)
        let admin = makeUser(role: .admin)
        #expect(shouldShowQuickToggle(for: day, user: admin, adminPreview: adminPreview(enabled: false), calendar: calendar))
    }

    @Test func adminDoesNotSeeQuickToggleOnPastDay() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now)!
        let day = SurveyDay(date: yesterday, groupID: nil)
        let admin = makeUser(role: .admin)
        #expect(!shouldShowQuickToggle(for: day, user: admin, adminPreview: adminPreview(enabled: false), calendar: calendar))
    }

    @Test func adminSeesQuickToggleOnToday() {
        let day = SurveyDay(date: .now, groupID: nil)
        let admin = makeUser(role: .admin)
        #expect(shouldShowQuickToggle(for: day, user: admin, adminPreview: adminPreview(enabled: false), calendar: calendar))
    }
}
