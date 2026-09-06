import Foundation

struct SurveyEntryWithDate {
    let entry: SurveyEntry
    let date: Date
}

enum SurveyRepositoryError: Error {
    /// The day was locked by an admin after this screen's data was loaded —
    /// callers should treat this like any other failed write (roll back
    /// optimistic UI, reload) rather than silently no-op.
    case dayLocked
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
    /// Same as calling `entries(forDayID:)` once per id, but in a single
    /// round trip — views that render a whole week block use this instead of
    /// looping, so opening/refreshing Umfragen isn't one network call per day.
    func entries(forDayIDs dayIDs: [UUID]) async throws -> [SurveyEntry]
    func signIn(userID: UUID, dayID: UUID) async throws
    func signOut(userID: UUID, dayID: UUID) async throws
    func setLocked(_ locked: Bool, reason: String?, dayID: UUID) async throws
    func entriesWithDates(inMonth month: Int, year: Int, groupID: UUID) async throws -> [SurveyEntryWithDate]
    /// All entries for the group, across all time — used for per-member
    /// lifetime/weekly/monthly trip stats (see MemberDetailView).
    func allEntriesWithDates(groupID: UUID) async throws -> [SurveyEntryWithDate]
}
