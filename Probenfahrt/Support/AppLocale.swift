import Foundation

extension Locale {
    /// UI language is German regardless of device/simulator locale (spec: "Zielgruppe/UI-Sprache: Deutsch").
    static let app = Locale(identifier: "de_DE")
}
