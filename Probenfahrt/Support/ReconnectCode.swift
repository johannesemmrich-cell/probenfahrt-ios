import Foundation

/// Wiedereinstiegs-Code: ein frei wählbarer, pro Gruppe eindeutiger
/// 3-Zeichen-Code (Buchstaben/Ziffern), den sich ein Labor-Mitglied unter
/// Einstellungen → Profil hinterlegt. Damit meldet es sich nach Verlassen
/// der Gruppe oder Session-Verlust im Onboarding per
/// "GruppenCode-Wiedereinstiegscode" direkt wieder mit seinem BESTEHENDEN
/// Konto an (gleiche User-UUID) — statt per Neu-Beitritt ein Duplikat zu
/// erzeugen, an dem Fahrten-/Umfragen-/Kalender-Historie nicht mehr hängt.
/// Wird ein Mitglied vom Admin entfernt, löscht `deleteUser` den Code mit,
/// sodass der Wiedereinstieg dann gesperrt ist.
enum ReconnectCode {
    static let length = 3

    /// Trimmt, lowercased und validiert: genau `length` ASCII-Buchstaben/
    /// Ziffern, sonst nil. Gespeichert und verglichen wird lowercased —
    /// gleiche Normalisierung wie bei Join-Codes und Kürzeln (CloudKit kann
    /// nicht zuverlässig case-insensitiv vergleichen).
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count == length,
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return trimmed
    }

    /// Zerlegt Onboarding-Eingaben der Form "GruppenCode-XYZ" am LETZTEN
    /// Bindestrich — Join-Codes dürfen selbst Bindestriche enthalten (z.B.
    /// "apple-review-demo"), der Wiedereinstiegs-Code nie (`normalize`
    /// lehnt ihn ab). Nil, wenn die Eingabe nicht wie ein Wiedereinstieg
    /// aussieht.
    static func splitLoginInput(_ input: String) -> (joinCode: String, code: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hyphen = trimmed.lastIndex(of: "-") else { return nil }
        let joinCode = String(trimmed[..<hyphen]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joinCode.isEmpty,
              let code = normalize(String(trimmed[trimmed.index(after: hyphen)...])) else { return nil }
        return (joinCode, code)
    }
}
