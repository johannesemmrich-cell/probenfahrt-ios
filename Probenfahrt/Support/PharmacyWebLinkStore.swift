import Foundation

/// Base URL of the Apotheken-Web-Check-in (BACKLOG #3, see web/worker/)
/// that every pharmacy's QR code points to. Live at mediproben.com since
/// 2026-09-14 (Cloudflare Worker) - still editable here in case a
/// staging/local URL is ever needed again.
@Observable
final class PharmacyWebLinkStore {
    private let storageKey = "com.johannesemmrich.probenfahrt.pharmacyWebBaseURL"
    private let defaultBaseURL = "https://mediproben.com"

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
