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

    /// QR-Scanner erkennen eine schemalose Basis-URL (z.B. "mediproben.com"
    /// statt "https://mediproben.com") oft gar nicht als Link oder werfen
    /// den "?token=..."-Teil weg - anders als eine Browser-Adressleiste,
    /// die das großzügig ergänzt. Deshalb hier hart absichern statt auf
    /// korrekte manuelle Eingabe im Basis-URL-Feld zu vertrauen.
    func checkInURL(token: String) -> String {
        let normalizedBase = baseURL.hasPrefix("http://") || baseURL.hasPrefix("https://")
            ? baseURL
            : "https://\(baseURL)"
        return "\(normalizedBase)?token=\(token)"
    }
}
