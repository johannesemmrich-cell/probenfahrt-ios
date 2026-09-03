import CloudKit
import Foundation

/// CloudKit-backed implementation of SamplesRepository (BACKLOG #1),
/// replacing the local SwiftData mock so the Proben tab reflects real,
/// shared team data — including check-ins from the QR-code webpage
/// (BACKLOG #3, see web/index.html).
///
/// Uses the CloudKit **public** database directly, not SwiftData's built-in
/// CloudKit sync — that only mirrors a single iCloud account's *private*
/// database, so it can't share data across the whole lab team or an
/// unauthenticated web page. Deliberately scoped to just SampleLocation/
/// SampleReport for now; the rest of the app (Umfragen, Kalender, Chat,
/// Mitglieder) stays on local SwiftData until BACKLOG #1 covers those too.
///
/// Requires the CloudKit Dashboard schema for both record types to mark
/// `groupID`/`locationID` (and `day` on SampleReport) as Queryable — see
/// the CloudKit setup checklist in README.md.
@MainActor
final class CloudKitSamplesRepository: SamplesRepository {
    private let database: CKDatabase

    init(container: CKContainer = CKContainer(identifier: CloudKitConfig.containerIdentifier)) {
        self.database = container.publicCloudDatabase
    }

    private enum RecordType {
        static let location = "SampleLocation"
        static let report = "SampleReport"
    }

    private enum LocationField {
        static let locationID = "locationID"
        static let groupID = "groupID"
        static let name = "name"
        static let address = "address"
        static let ownerUserID = "ownerUserID"
        static let token = "token"
        static let usesQRCheckIn = "usesQRCheckIn"
    }

    private enum ReportField {
        static let reportID = "reportID"
        static let locationID = "locationID"
        static let groupID = "groupID"
        static let day = "day"
        static let hasSamples = "hasSamples"
        static let statusNote = "statusNote"
        static let reportedAt = "reportedAt"
    }

    // MARK: - SamplesRepository

    func locations(groupID: UUID) async throws -> [SampleLocation] {
        let predicate = NSPredicate(format: "%K == %@", LocationField.groupID, groupID.uuidString)
        let query = CKQuery(recordType: RecordType.location, predicate: predicate)
        return try await allRecords(matching: query)
            .map(Self.location(from:))
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func findOrCreateLocation(ownerUserID: UUID, groupID: UUID, name: String) async throws -> SampleLocation {
        let recordID = Self.ownerLocationRecordID(ownerUserID: ownerUserID)
        if let existing = try? await database.record(for: recordID) {
            return Self.location(from: existing)
        }
        // Self-service pharmacy accounts use PharmacySamplesView inside the
        // app itself, never the QR web check-in — no QR code to show.
        let location = SampleLocation(groupID: groupID, name: name, address: "", ownerUserID: ownerUserID, usesQRCheckIn: false)
        let record = CKRecord(recordType: RecordType.location, recordID: recordID)
        Self.apply(location, to: record)
        let saved = try await database.save(record)
        return Self.location(from: saved)
    }

    func createLocation(groupID: UUID, name: String, address: String, usesQRCheckIn: Bool) async throws -> SampleLocation {
        let location = SampleLocation(groupID: groupID, name: name, address: address, usesQRCheckIn: usesQRCheckIn)
        let record = CKRecord(recordType: RecordType.location, recordID: Self.locationRecordID(id: location.id))
        Self.apply(location, to: record)
        let saved = try await database.save(record)
        return Self.location(from: saved)
    }

    func reports(groupID: UUID, day: Date) async throws -> [SampleReport] {
        let normalizedDay = SampleReport.normalizedDay(day)
        let predicate = NSPredicate(
            format: "%K == %@ AND %K == %@",
            ReportField.groupID, groupID.uuidString,
            ReportField.day, normalizedDay as NSDate
        )
        let query = CKQuery(recordType: RecordType.report, predicate: predicate)
        return try await allRecords(matching: query).map(Self.report(from:))
    }

    func report(locationID: UUID, day: Date) async throws -> SampleReport? {
        let normalizedDay = SampleReport.normalizedDay(day)
        let recordID = Self.reportRecordID(locationID: locationID, day: normalizedDay)
        guard let record = try? await database.record(for: recordID) else { return nil }
        return Self.report(from: record)
    }

    func reports(groupID: UUID, inMonth month: Int, year: Int) async throws -> [SampleReport] {
        let calendar = Calendar.current
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = month
        startComponents.day = 1
        guard let start = calendar.date(from: startComponents),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else { return [] }
        let predicate = NSPredicate(
            format: "%K == %@ AND %K >= %@ AND %K < %@",
            ReportField.groupID, groupID.uuidString,
            ReportField.day, start as NSDate,
            ReportField.day, end as NSDate
        )
        let query = CKQuery(recordType: RecordType.report, predicate: predicate)
        return try await allRecords(matching: query).map(Self.report(from:))
    }

    func reports(groupID: UUID, from: Date, to: Date) async throws -> [SampleReport] {
        let calendar = Calendar.current
        let start = SampleReport.normalizedDay(from)
        guard let end = calendar.date(byAdding: .day, value: 1, to: SampleReport.normalizedDay(to)) else { return [] }
        let predicate = NSPredicate(
            format: "%K == %@ AND %K >= %@ AND %K < %@",
            ReportField.groupID, groupID.uuidString,
            ReportField.day, start as NSDate,
            ReportField.day, end as NSDate
        )
        let query = CKQuery(recordType: RecordType.report, predicate: predicate)
        return try await allRecords(matching: query).map(Self.report(from:))
    }

    func setHasSamples(_ hasSamples: Bool, locationID: UUID, day: Date) async throws {
        let normalizedDay = SampleReport.normalizedDay(day)
        let recordID = Self.reportRecordID(locationID: locationID, day: normalizedDay)
        if let existing = try? await database.record(for: recordID) {
            existing[ReportField.hasSamples] = hasSamples ? 1 : 0
            existing[ReportField.reportedAt] = Date.now as CKRecordValue
            _ = try await database.save(existing)
            return
        }
        guard let location = try await fetchLocation(id: locationID) else { return }
        let report = SampleReport(locationID: locationID, groupID: location.groupID, day: normalizedDay, hasSamples: hasSamples)
        let record = CKRecord(recordType: RecordType.report, recordID: recordID)
        Self.apply(report, to: record)
        _ = try await database.save(record)
    }

    func deleteLocationIfOwned(by ownerUserID: UUID) async throws {
        let recordID = Self.ownerLocationRecordID(ownerUserID: ownerUserID)
        guard let locationRecord = try? await database.record(for: recordID) else { return }
        let location = Self.location(from: locationRecord)
        let predicate = NSPredicate(format: "%K == %@", ReportField.locationID, location.id.uuidString)
        let query = CKQuery(recordType: RecordType.report, predicate: predicate)
        if let reportRecords = try? await allRecords(matching: query) {
            for reportRecord in reportRecords {
                try? await database.deleteRecord(withID: reportRecord.recordID)
            }
        }
        try? await database.deleteRecord(withID: recordID)
    }

    func deleteLocation(id: UUID, ownerUserID: UUID?) async throws {
        let recordID = ownerUserID.map(Self.ownerLocationRecordID(ownerUserID:)) ?? Self.locationRecordID(id: id)
        let predicate = NSPredicate(format: "%K == %@", ReportField.locationID, id.uuidString)
        let query = CKQuery(recordType: RecordType.report, predicate: predicate)
        if let reportRecords = try? await allRecords(matching: query) {
            for reportRecord in reportRecords {
                try? await database.deleteRecord(withID: reportRecord.recordID)
            }
        }
        // Unlike deleteLocationIfOwned's best-effort cleanup, this is an
        // explicit admin action — a failure here should surface as a real
        // error in the UI, not fail silently.
        try await database.deleteRecord(withID: recordID)
    }

    // MARK: - Helpers

    private func fetchLocation(id: UUID) async throws -> SampleLocation? {
        let predicate = NSPredicate(format: "%K == %@", LocationField.locationID, id.uuidString)
        let query = CKQuery(recordType: RecordType.location, predicate: predicate)
        guard let record = try await allRecords(matching: query).first else { return nil }
        return Self.location(from: record)
    }

    /// Pages through `CKQueryOperation.Cursor` until all matching records
    /// are collected — CloudKit caps a single response's result count.
    private func allRecords(matching query: CKQuery) async throws -> [CKRecord] {
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
                // results. That's the normal state before the first
                // SampleReport is ever saved, so treat it as "no data yet"
                // rather than a real failure.
                if Self.isUnknownRecordType(error) { return records }
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

    // MARK: - Record IDs

    private static func ownerLocationRecordID(ownerUserID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "location-owner-\(ownerUserID.uuidString)")
    }

    private static func locationRecordID(id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "location-\(id.uuidString)")
    }

    /// Builds the day suffix from local calendar components rather than
    /// ISO8601DateFormatter (which defaults to UTC) — `day` is already a
    /// Calendar.current.startOfDay(for:) instant, so formatting it in UTC
    /// could shift it to the wrong calendar date depending on time of day.
    private static func reportRecordID(locationID: UUID, day: Date) -> CKRecord.ID {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        let dayString = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        return CKRecord.ID(recordName: "report-\(locationID.uuidString)-\(dayString)")
    }

    // MARK: - CKRecord <-> model mapping

    private static func apply(_ location: SampleLocation, to record: CKRecord) {
        record[LocationField.locationID] = location.id.uuidString as CKRecordValue
        record[LocationField.groupID] = location.groupID?.uuidString as CKRecordValue?
        record[LocationField.name] = location.name as CKRecordValue
        record[LocationField.address] = location.address as CKRecordValue
        record[LocationField.ownerUserID] = location.ownerUserID?.uuidString as CKRecordValue?
        record[LocationField.token] = location.token as CKRecordValue
        record[LocationField.usesQRCheckIn] = (location.usesQRCheckIn ? 1 : 0) as CKRecordValue
    }

    private static func location(from record: CKRecord) -> SampleLocation {
        let id = (record[LocationField.locationID] as? String).flatMap(UUID.init) ?? UUID()
        let groupID = (record[LocationField.groupID] as? String).flatMap(UUID.init)
        let ownerUserID = (record[LocationField.ownerUserID] as? String).flatMap(UUID.init)
        let token = (record[LocationField.token] as? String) ?? UUID().uuidString
        // Locations saved before this field existed have no usesQRCheckIn
        // value at all — default true so their existing QR codes keep working.
        let usesQRCheckIn = ((record[LocationField.usesQRCheckIn] as? Int64) ?? 1) != 0
        return SampleLocation(
            id: id,
            groupID: groupID,
            name: (record[LocationField.name] as? String) ?? "",
            address: (record[LocationField.address] as? String) ?? "",
            ownerUserID: ownerUserID,
            token: token,
            usesQRCheckIn: usesQRCheckIn
        )
    }

    private static func apply(_ report: SampleReport, to record: CKRecord) {
        record[ReportField.reportID] = report.id.uuidString as CKRecordValue
        record[ReportField.locationID] = report.locationID.uuidString as CKRecordValue
        record[ReportField.groupID] = report.groupID?.uuidString as CKRecordValue?
        record[ReportField.day] = report.day as CKRecordValue
        record[ReportField.hasSamples] = (report.hasSamples ? 1 : 0) as CKRecordValue
        record[ReportField.statusNote] = report.statusNote as CKRecordValue
        record[ReportField.reportedAt] = report.reportedAt as CKRecordValue
    }

    private static func report(from record: CKRecord) -> SampleReport {
        let id = (record[ReportField.reportID] as? String).flatMap(UUID.init) ?? UUID()
        let locationID = (record[ReportField.locationID] as? String).flatMap(UUID.init) ?? UUID()
        let groupID = (record[ReportField.groupID] as? String).flatMap(UUID.init)
        let day = (record[ReportField.day] as? Date) ?? .now
        let hasSamples = ((record[ReportField.hasSamples] as? Int64) ?? 0) != 0
        let statusNote = (record[ReportField.statusNote] as? String) ?? ""
        let reportedAt = (record[ReportField.reportedAt] as? Date) ?? .now
        return SampleReport(
            id: id,
            locationID: locationID,
            groupID: groupID,
            day: day,
            hasSamples: hasSamples,
            statusNote: statusNote,
            reportedAt: reportedAt
        )
    }
}
