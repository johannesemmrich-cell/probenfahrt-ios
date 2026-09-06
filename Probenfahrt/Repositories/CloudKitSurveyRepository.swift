import CloudKit
import Foundation

/// CloudKit-backed implementation of SurveyRepository (BACKLOG #1), replacing
/// the local SwiftData mock so Umfragen/Kalender real, shared team data
/// reflect — analog to CloudKitSamplesRepository for the Proben-Bereich.
///
/// Requires the CloudKit Dashboard schema for both record types to mark
/// `groupID`/`date`/`dayID` (SurveyDay) and `surveyDayID`/`groupID`
/// (SurveyEntry) as Queryable — see the CloudKit setup checklist in README.md.
@MainActor
final class CloudKitSurveyRepository: SurveyRepository {
    private let database: CKDatabase
    private let calendar = Calendar.current

    init(container: CKContainer = CKContainer(identifier: CloudKitConfig.containerIdentifier)) {
        self.database = container.publicCloudDatabase
    }

    private enum RecordType {
        static let day = "SurveyDay"
        static let entry = "SurveyEntry"
    }

    private enum DayField {
        static let dayID = "dayID"
        static let groupID = "groupID"
        static let date = "date"
        static let isLocked = "isLocked"
        static let lockReason = "lockReason"
    }

    private enum EntryField {
        static let entryID = "entryID"
        static let surveyDayID = "surveyDayID"
        static let userID = "userID"
        static let groupID = "groupID"
        static let createdAt = "createdAt"
    }

    // MARK: - SurveyRepository

    func surveyDays(from startDate: Date, to endDate: Date, groupID: UUID) async throws -> [SurveyDay] {
        try await ensureDaysExist(from: startDate, to: endDate, groupID: groupID)
        return try await daysInRange(
            start: calendar.startOfDay(for: startDate),
            end: calendar.startOfDay(for: endDate),
            groupID: groupID
        )
    }

    func existingSurveyDays(from startDate: Date, to endDate: Date, groupID: UUID) async throws -> [SurveyDay] {
        try await daysInRange(
            start: calendar.startOfDay(for: startDate),
            end: calendar.startOfDay(for: endDate),
            groupID: groupID
        )
    }

    func entries(forDayID dayID: UUID) async throws -> [SurveyEntry] {
        let predicate = NSPredicate(format: "%K == %@", EntryField.surveyDayID, dayID.uuidString)
        let query = CKQuery(recordType: RecordType.entry, predicate: predicate)
        return try await allRecords(matching: query).map(Self.entry(from:))
    }

    func entries(forDayIDs dayIDs: [UUID]) async throws -> [SurveyEntry] {
        guard !dayIDs.isEmpty else { return [] }
        let predicate = NSPredicate(format: "%K IN %@", EntryField.surveyDayID, dayIDs.map(\.uuidString))
        let query = CKQuery(recordType: RecordType.entry, predicate: predicate)
        return try await allRecords(matching: query).map(Self.entry(from:))
    }

    func signIn(userID: UUID, dayID: UUID) async throws {
        guard let day = try await fetchDay(id: dayID) else { return }
        guard !day.isLocked else { throw SurveyRepositoryError.dayLocked }
        let recordID = Self.entryRecordID(dayID: dayID, userID: userID)
        guard (try? await database.record(for: recordID)) == nil else { return }
        let entry = SurveyEntry(surveyDayID: dayID, userID: userID, groupID: day.groupID)
        let record = CKRecord(recordType: RecordType.entry, recordID: recordID)
        Self.apply(entry, to: record)
        _ = try await database.save(record)
    }

    func signOut(userID: UUID, dayID: UUID) async throws {
        _ = try? await database.deleteRecord(withID: Self.entryRecordID(dayID: dayID, userID: userID))
    }

    func setLocked(_ locked: Bool, reason: String?, dayID: UUID) async throws {
        guard let record = try await dayRecord(id: dayID) else { return }
        record[DayField.isLocked] = (locked ? 1 : 0) as CKRecordValue
        record[DayField.lockReason] = locked ? (reason as CKRecordValue?) : nil
        _ = try await database.save(record)
    }

    func entriesWithDates(inMonth month: Int, year: Int, groupID: UUID) async throws -> [SurveyEntryWithDate] {
        let matchingDays = try await allDays(groupID: groupID).filter {
            calendar.component(.year, from: $0.date) == year && calendar.component(.month, from: $0.date) == month
        }
        return try await joinedEntries(days: matchingDays, groupID: groupID)
    }

    func allEntriesWithDates(groupID: UUID) async throws -> [SurveyEntryWithDate] {
        try await joinedEntries(days: allDays(groupID: groupID), groupID: groupID)
    }

    // MARK: - Helpers

    private func joinedEntries(days: [SurveyDay], groupID: UUID) async throws -> [SurveyEntryWithDate] {
        let dateByDayID = Dictionary(uniqueKeysWithValues: days.map { ($0.id, $0.date) })
        return try await allEntries(groupID: groupID).compactMap { entry in
            guard let dayID = entry.surveyDayID, let date = dateByDayID[dayID] else { return nil }
            return SurveyEntryWithDate(entry: entry, date: date)
        }
    }

    private func ensureDaysExist(from startDate: Date, to endDate: Date, groupID: UUID) async throws {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        var existingDates = Set(try await daysInRange(start: start, end: end, groupID: groupID).map { calendar.startOfDay(for: $0.date) })

        var cursor = start
        while cursor <= end {
            let weekday = calendar.component(.weekday, from: cursor)
            if (2...5).contains(weekday), !existingDates.contains(cursor) {
                let day = SurveyDay(date: cursor, groupID: groupID)
                let record = CKRecord(recordType: RecordType.day, recordID: Self.dayRecordID(groupID: groupID, date: cursor))
                Self.apply(day, to: record)
                // Best-effort: two devices lazily creating the same missing
                // day at once can race on this deterministic ID — matches
                // the same known, documented tradeoff as SampleReport's
                // read-then-write race (BACKLOG #4), not fixed here.
                _ = try? await database.save(record)
                existingDates.insert(cursor)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
    }

    private func daysInRange(start: Date, end: Date, groupID: UUID) async throws -> [SurveyDay] {
        let predicate = NSPredicate(
            format: "%K == %@ AND %K >= %@ AND %K <= %@",
            DayField.groupID, groupID.uuidString,
            DayField.date, start as NSDate,
            DayField.date, end as NSDate
        )
        let query = CKQuery(recordType: RecordType.day, predicate: predicate)
        return try await allRecords(matching: query).map(Self.day(from:)).sorted { $0.date < $1.date }
    }

    private func allDays(groupID: UUID) async throws -> [SurveyDay] {
        let predicate = NSPredicate(format: "%K == %@", DayField.groupID, groupID.uuidString)
        let query = CKQuery(recordType: RecordType.day, predicate: predicate)
        return try await allRecords(matching: query).map(Self.day(from:))
    }

    private func allEntries(groupID: UUID) async throws -> [SurveyEntry] {
        let predicate = NSPredicate(format: "%K == %@", EntryField.groupID, groupID.uuidString)
        let query = CKQuery(recordType: RecordType.entry, predicate: predicate)
        return try await allRecords(matching: query).map(Self.entry(from:))
    }

    private func dayRecord(id: UUID) async throws -> CKRecord? {
        let predicate = NSPredicate(format: "%K == %@", DayField.dayID, id.uuidString)
        let query = CKQuery(recordType: RecordType.day, predicate: predicate)
        return try await allRecords(matching: query).first
    }

    private func fetchDay(id: UUID) async throws -> SurveyDay? {
        guard let record = try await dayRecord(id: id) else { return nil }
        return Self.day(from: record)
    }

    private func allRecords(matching query: CKQuery) async throws -> [CKRecord] {
        try await CloudKitQuerying.allRecords(matching: query, in: database)
    }

    // MARK: - Record IDs

    private static func dayRecordID(groupID: UUID, date: Date) -> CKRecord.ID {
        CKRecord.ID(recordName: "surveyday-\(groupID.uuidString)-\(CloudKitQuerying.localDayString(for: date))")
    }

    private static func entryRecordID(dayID: UUID, userID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "entry-\(dayID.uuidString)-\(userID.uuidString)")
    }

    // MARK: - CKRecord <-> model mapping

    private static func apply(_ day: SurveyDay, to record: CKRecord) {
        record[DayField.dayID] = day.id.uuidString as CKRecordValue
        record[DayField.groupID] = day.groupID?.uuidString as CKRecordValue?
        record[DayField.date] = day.date as CKRecordValue
        record[DayField.isLocked] = (day.isLocked ? 1 : 0) as CKRecordValue
        record[DayField.lockReason] = day.lockReason as CKRecordValue?
    }

    private static func day(from record: CKRecord) -> SurveyDay {
        let id = (record[DayField.dayID] as? String).flatMap(UUID.init) ?? UUID()
        let groupID = (record[DayField.groupID] as? String).flatMap(UUID.init)
        let isLocked = ((record[DayField.isLocked] as? Int64) ?? 0) != 0
        return SurveyDay(
            id: id,
            date: (record[DayField.date] as? Date) ?? .now,
            groupID: groupID,
            isLocked: isLocked,
            lockReason: record[DayField.lockReason] as? String
        )
    }

    private static func apply(_ entry: SurveyEntry, to record: CKRecord) {
        record[EntryField.entryID] = entry.id.uuidString as CKRecordValue
        record[EntryField.surveyDayID] = entry.surveyDayID?.uuidString as CKRecordValue?
        record[EntryField.userID] = entry.userID?.uuidString as CKRecordValue?
        record[EntryField.groupID] = entry.groupID?.uuidString as CKRecordValue?
        record[EntryField.createdAt] = entry.createdAt as CKRecordValue
    }

    private static func entry(from record: CKRecord) -> SurveyEntry {
        let id = (record[EntryField.entryID] as? String).flatMap(UUID.init) ?? UUID()
        let surveyDayID = (record[EntryField.surveyDayID] as? String).flatMap(UUID.init)
        let userID = (record[EntryField.userID] as? String).flatMap(UUID.init)
        let groupID = (record[EntryField.groupID] as? String).flatMap(UUID.init)
        return SurveyEntry(
            id: id,
            surveyDayID: surveyDayID,
            userID: userID,
            groupID: groupID,
            createdAt: (record[EntryField.createdAt] as? Date) ?? .now
        )
    }
}
