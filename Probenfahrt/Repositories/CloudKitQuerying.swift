import CloudKit
import Foundation

/// Shared CloudKit public-database query paging, used by every CloudKit-backed
/// repository (Samples, User, Survey, Chat) instead of each duplicating the
/// same cursor-paging + "record type doesn't exist yet" handling.
enum CloudKitQuerying {
    /// Pages through `CKQueryOperation.Cursor` until all matching records
    /// are collected — CloudKit caps a single response's result count.
    static func allRecords(matching query: CKQuery, in database: CKDatabase) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let result: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            do {
                if let cursor {
                    result = try await database.records(continuingMatchFrom: cursor)
                } else {
                    result = try await database.records(matching: query)
                }
            } catch {
                // A record type with no records saved yet doesn't exist in
                // CloudKit's schema — querying it errors ("Did not find
                // record type: ...") instead of just returning zero
                // results. That's the normal state before the first record
                // of that type is ever saved, so treat it as "no data yet"
                // rather than a real failure.
                if isUnknownRecordType(error) { return records }
                throw error
            }
            records.append(contentsOf: result.matchResults.compactMap { try? $0.1.get() })
            cursor = result.queryCursor
        } while cursor != nil
        return records
    }

    private static func isUnknownRecordType(_ error: Error) -> Bool {
        if let ckError = error as? CKError, ckError.code == .unknownItem { return true }
        return error.localizedDescription.contains("Did not find record type")
    }

    /// Formats a date's local calendar day as "yyyy-MM-dd" — used to build
    /// deterministic per-day CKRecord.IDs. Deliberately built from local
    /// `Calendar` components rather than ISO8601DateFormatter (which
    /// defaults to UTC): callers pass a `Calendar.current.startOfDay(for:)`
    /// instant, so formatting it in UTC could shift it to the wrong
    /// calendar date depending on time of day.
    static func localDayString(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
