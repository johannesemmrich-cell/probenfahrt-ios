import Foundation
import SwiftData

struct SurveyEntryWithDate {
    let entry: SurveyEntry
    let date: Date
}

@MainActor
protocol SurveyRepository {
    /// Fetches survey days (Mon–Thu only) in the given range, lazily creating
    /// any that don't exist yet — so the rolling window always has real rows
    /// to sign into, however far in the future it's requested.
    func surveyDays(from startDate: Date, to endDate: Date, groupID: UUID) async throws -> [SurveyDay]
    /// Same as `surveyDays`, but never creates missing days — for read-only
    /// screens (Kalender, vergangene Umfragen) that must not have side effects.
    func existingSurveyDays(from startDate: Date, to endDate: Date, groupID: UUID) async throws -> [SurveyDay]
    func entries(forDayID dayID: UUID) async throws -> [SurveyEntry]
    func signIn(userID: UUID, dayID: UUID) async throws
    func signOut(userID: UUID, dayID: UUID) async throws
    func setLocked(_ locked: Bool, reason: String?, dayID: UUID) async throws
    func entriesWithDates(inMonth month: Int, year: Int, groupID: UUID) async throws -> [SurveyEntryWithDate]
    /// All entries for the group, across all time — used for per-member
    /// lifetime/weekly/monthly trip stats (see MemberDetailView).
    func allEntriesWithDates(groupID: UUID) async throws -> [SurveyEntryWithDate]
}

@MainActor
final class SwiftDataSurveyRepository: SurveyRepository {
    private let context: ModelContext
    private let calendar = Calendar.current

    init(context: ModelContext) {
        self.context = context
    }

    func surveyDays(from startDate: Date, to endDate: Date, groupID: UUID) async throws -> [SurveyDay] {
        try ensureDaysExist(from: startDate, to: endDate, groupID: groupID)
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let all = try context.fetch(FetchDescriptor<SurveyDay>(predicate: #Predicate<SurveyDay> { $0.groupID == groupID }))
        return all
            .filter { $0.date >= start && $0.date <= end }
            .sorted { $0.date < $1.date }
    }

    func existingSurveyDays(from startDate: Date, to endDate: Date, groupID: UUID) async throws -> [SurveyDay] {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let all = try context.fetch(FetchDescriptor<SurveyDay>(predicate: #Predicate<SurveyDay> { $0.groupID == groupID }))
        return all
            .filter { $0.date >= start && $0.date <= end }
            .sorted { $0.date < $1.date }
    }

    func entries(forDayID dayID: UUID) async throws -> [SurveyEntry] {
        try context.fetch(FetchDescriptor<SurveyEntry>(predicate: #Predicate<SurveyEntry> { $0.surveyDayID == dayID }))
    }

    func signIn(userID: UUID, dayID: UUID) async throws {
        guard let day = try fetchDay(id: dayID), !day.isLocked else { return }
        let existing = try context.fetch(FetchDescriptor<SurveyEntry>(predicate: #Predicate<SurveyEntry> {
            $0.surveyDayID == dayID && $0.userID == userID
        }))
        guard existing.isEmpty else { return }
        context.insert(SurveyEntry(surveyDayID: dayID, userID: userID))
        try context.save()
    }

    func signOut(userID: UUID, dayID: UUID) async throws {
        let matches = try context.fetch(FetchDescriptor<SurveyEntry>(predicate: #Predicate<SurveyEntry> {
            $0.surveyDayID == dayID && $0.userID == userID
        }))
        matches.forEach { context.delete($0) }
        try context.save()
    }

    func setLocked(_ locked: Bool, reason: String?, dayID: UUID) async throws {
        guard let day = try fetchDay(id: dayID) else { return }
        day.isLocked = locked
        day.lockReason = locked ? reason : nil
        try context.save()
    }

    func entriesWithDates(inMonth month: Int, year: Int, groupID: UUID) async throws -> [SurveyEntryWithDate] {
        let allDays = try context.fetch(FetchDescriptor<SurveyDay>(predicate: #Predicate<SurveyDay> { $0.groupID == groupID }))
        let matchingDays = allDays.filter {
            calendar.component(.year, from: $0.date) == year && calendar.component(.month, from: $0.date) == month
        }
        let dateByDayID = Dictionary(uniqueKeysWithValues: matchingDays.map { ($0.id, $0.date) })

        let allEntries = try context.fetch(FetchDescriptor<SurveyEntry>())
        return allEntries.compactMap { entry in
            guard let dayID = entry.surveyDayID, let date = dateByDayID[dayID] else { return nil }
            return SurveyEntryWithDate(entry: entry, date: date)
        }
    }

    func allEntriesWithDates(groupID: UUID) async throws -> [SurveyEntryWithDate] {
        let allDays = try context.fetch(FetchDescriptor<SurveyDay>(predicate: #Predicate<SurveyDay> { $0.groupID == groupID }))
        let dateByDayID = Dictionary(uniqueKeysWithValues: allDays.map { ($0.id, $0.date) })

        let allEntries = try context.fetch(FetchDescriptor<SurveyEntry>())
        return allEntries.compactMap { entry in
            guard let dayID = entry.surveyDayID, let date = dateByDayID[dayID] else { return nil }
            return SurveyEntryWithDate(entry: entry, date: date)
        }
    }

    private func fetchDay(id: UUID) throws -> SurveyDay? {
        try context.fetch(FetchDescriptor<SurveyDay>(predicate: #Predicate<SurveyDay> { $0.id == id })).first
    }

    private func ensureDaysExist(from startDate: Date, to endDate: Date, groupID: UUID) throws {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)

        let existing = try context.fetch(FetchDescriptor<SurveyDay>(predicate: #Predicate<SurveyDay> { $0.groupID == groupID }))
        var existingDates = Set(existing.map { calendar.startOfDay(for: $0.date) })

        var cursor = start
        var didInsert = false
        while cursor <= end {
            let weekday = calendar.component(.weekday, from: cursor)
            if (2...5).contains(weekday), !existingDates.contains(cursor) {
                context.insert(SurveyDay(date: cursor, groupID: groupID))
                existingDates.insert(cursor)
                didInsert = true
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        if didInsert {
            try context.save()
        }
    }
}
