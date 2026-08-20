import Foundation

enum MonthlyReportGenerator {
    struct ReportLine: Identifiable {
        var id: UUID { userID }
        let userID: UUID
        let userName: String
        let tripCount: Int
    }

    /// Aggregates trip counts per user for the admin monthly PDF export,
    /// e.g. "Johannes: 7 Fahrten". Sorted by trip count descending, then by name.
    static func generate(entries: [SurveyEntryWithDate], users: [User]) -> [ReportLine] {
        let userByID = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        var counts: [UUID: Int] = [:]
        for entryWithDate in entries {
            guard let userID = entryWithDate.entry.userID else { continue }
            counts[userID, default: 0] += 1
        }
        return counts.compactMap { userID, count -> ReportLine? in
            guard let user = userByID[userID] else { return nil }
            return ReportLine(userID: userID, userName: user.name, tripCount: count)
        }
        .sorted { lhs, rhs in
            if lhs.tripCount != rhs.tripCount {
                return lhs.tripCount > rhs.tripCount
            }
            return lhs.userName < rhs.userName
        }
    }
}
