import Foundation

struct AppUpdateInfo: Equatable {
    let availableVersion: String
    let appStoreURL: URL
}

/// Looks up the version currently live on the App Store via Apple's public,
/// unauthenticated iTunes Lookup API (no App Store Connect API key needed)
/// and compares it against the installed build — powers the "Update
/// verfügbar" banner in RootTabView.
enum AppUpdateChecker {
    static func checkForUpdate() async -> AppUpdateInfo? {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let installedVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }

        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [URLQueryItem(name: "bundleId", value: bundleID)]
        guard let url = components.url else { return nil }

        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(LookupResponse.self, from: data),
              let entry = response.results.first,
              let storeURL = URL(string: entry.trackViewUrl) else {
            return nil
        }

        guard isVersion(entry.version, newerThan: installedVersion) else { return nil }
        return AppUpdateInfo(availableVersion: entry.version, appStoreURL: storeURL)
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(aParts.count, bParts.count) {
            let x = i < aParts.count ? aParts[i] : 0
            let y = i < bParts.count ? bParts[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private struct LookupResponse: Decodable {
        let results: [LookupResult]
    }

    private struct LookupResult: Decodable {
        let version: String
        let trackViewUrl: String
    }
}
