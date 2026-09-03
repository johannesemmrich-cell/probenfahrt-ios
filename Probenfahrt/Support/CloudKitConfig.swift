import Foundation

enum CloudKitConfig {
    /// Must match `com.apple.developer.icloud-container-identifiers` in
    /// Probenfahrt.entitlements and the container selected in the CloudKit
    /// Dashboard (icloud.developer.apple.com).
    static let containerIdentifier = "iCloud.com.johannesemmrich.probenfahrt"
}
