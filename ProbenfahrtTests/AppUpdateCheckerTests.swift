import Testing
@testable import Probenfahrt

struct AppUpdateCheckerTests {
    @Test func detectsNewerMajorVersion() {
        #expect(AppUpdateChecker.isVersion("2.0", newerThan: "1.0"))
    }

    @Test func detectsNewerPatchVersion() {
        #expect(AppUpdateChecker.isVersion("1.0.1", newerThan: "1.0.0"))
        #expect(AppUpdateChecker.isVersion("1.0.1", newerThan: "1.0"))
    }

    @Test func sameVersionIsNotNewer() {
        #expect(!AppUpdateChecker.isVersion("1.0", newerThan: "1.0"))
        #expect(!AppUpdateChecker.isVersion("1.0.0", newerThan: "1.0"))
    }

    @Test func olderVersionIsNotNewer() {
        #expect(!AppUpdateChecker.isVersion("1.0", newerThan: "1.1"))
        #expect(!AppUpdateChecker.isVersion("1.9", newerThan: "1.10"))
    }
}
