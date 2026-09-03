import Foundation

/// Base URL of the Apotheken-Web-Check-in (BACKLOG #3, see web/index.html)
/// that every pharmacy's QR code points to. Starts out as a plain
/// `python3 -m http.server` on localhost/the Mac's LAN IP; editable here so
/// it can move to a real hosted URL later without a code change.
@Observable
final class PharmacyWebLinkStore {
    private let storageKey = "com.johannesemmrich.probenfahrt.pharmacyWebBaseURL"
    private let defaultBaseURL = "http://localhost:8080"

    var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: storageKey) }
    }

    init() {
        baseURL = UserDefaults.standard.string(forKey: storageKey) ?? defaultBaseURL
    }

    func checkInURL(token: String) -> String {
        "\(baseURL)?token=\(token)"
    }
}
