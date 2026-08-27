import Foundation
import SwiftData

@MainActor
protocol SamplesRepository {
    func locations(groupID: UUID) async throws -> [SampleLocation]
    /// The location a pharmacy account manages itself, creating it on first
    /// use (also used by the DevMode "Proben (Test)" preview tab for a
    /// lab-team account, so it always has something to toggle).
    func findOrCreateLocation(ownerUserID: UUID, groupID: UUID, name: String) async throws -> SampleLocation
    /// All reports for a group's locations on one calendar day — the basis
    /// for both the "heute"-only Proben tab and day-by-day browsing of past
    /// reports.
    func reports(groupID: UUID, day: Date) async throws -> [SampleReport]
    /// A single location's report for one calendar day, e.g. so a pharmacy
    /// account can see its own current status.
    func report(locationID: UUID, day: Date) async throws -> SampleReport?
    /// All reports for a group's locations within one calendar month — the
    /// admin Proben-Auswertung PDF's data source, mirroring
    /// SurveyRepository.entriesWithDates(inMonth:year:groupID:).
    func reports(groupID: UUID, inMonth month: Int, year: Int) async throws -> [SampleReport]
    func setHasSamples(_ hasSamples: Bool, locationID: UUID, day: Date) async throws
    /// Cleans up a location created via `findOrCreateLocation` (and all of
    /// its reports) once it's no longer needed — e.g. when a DevMode
    /// pharmacy-preview toggle (see SettingsView) is switched back off, so
    /// the preview doesn't leave a permanent, team-visible entry under the
    /// tester's real name.
    func deleteLocationIfOwned(by ownerUserID: UUID) async throws
}

@MainActor
final class SwiftDataSamplesRepository: SamplesRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func locations(groupID: UUID) async throws -> [SampleLocation] {
        try context.fetch(FetchDescriptor<SampleLocation>(predicate: #Predicate<SampleLocation> { $0.groupID == groupID }))
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func findOrCreateLocation(ownerUserID: UUID, groupID: UUID, name: String) async throws -> SampleLocation {
        let existing = try context.fetch(FetchDescriptor<SampleLocation>(predicate: #Predicate<SampleLocation> {
            $0.ownerUserID == ownerUserID
        }))
        if let found = existing.first {
            return found
        }
        let location = SampleLocation(groupID: groupID, name: name, address: "", ownerUserID: ownerUserID)
        context.insert(location)
        try context.save()
        return location
    }

    func reports(groupID: UUID, day: Date) async throws -> [SampleReport] {
        let normalizedDay = SampleReport.normalizedDay(day)
        return try context.fetch(FetchDescriptor<SampleReport>(predicate: #Predicate<SampleReport> {
            $0.groupID == groupID && $0.day == normalizedDay
        }))
    }

    func report(locationID: UUID, day: Date) async throws -> SampleReport? {
        let normalizedDay = SampleReport.normalizedDay(day)
        return try context.fetch(FetchDescriptor<SampleReport>(predicate: #Predicate<SampleReport> {
            $0.locationID == locationID && $0.day == normalizedDay
        })).first
    }

    func reports(groupID: UUID, inMonth month: Int, year: Int) async throws -> [SampleReport] {
        let calendar = Calendar.current
        let all = try context.fetch(FetchDescriptor<SampleReport>(predicate: #Predicate<SampleReport> { $0.groupID == groupID }))
        return all.filter {
            calendar.component(.year, from: $0.day) == year && calendar.component(.month, from: $0.day) == month
        }
    }

    func setHasSamples(_ hasSamples: Bool, locationID: UUID, day: Date) async throws {
        let normalizedDay = SampleReport.normalizedDay(day)
        if let existing = try context.fetch(FetchDescriptor<SampleReport>(predicate: #Predicate<SampleReport> {
            $0.locationID == locationID && $0.day == normalizedDay
        })).first {
            existing.hasSamples = hasSamples
            existing.reportedAt = .now
            try context.save()
            return
        }
        guard let location = try context.fetch(FetchDescriptor<SampleLocation>(predicate: #Predicate<SampleLocation> {
            $0.id == locationID
        })).first else { return }
        let report = SampleReport(locationID: locationID, groupID: location.groupID, day: normalizedDay, hasSamples: hasSamples)
        context.insert(report)
        try context.save()
    }

    func deleteLocationIfOwned(by ownerUserID: UUID) async throws {
        let owned = try context.fetch(FetchDescriptor<SampleLocation>(predicate: #Predicate<SampleLocation> {
            $0.ownerUserID == ownerUserID
        }))
        guard !owned.isEmpty else { return }
        for location in owned {
            let locationID = location.id
            let reports = try context.fetch(FetchDescriptor<SampleReport>(predicate: #Predicate<SampleReport> {
                $0.locationID == locationID
            }))
            reports.forEach { context.delete($0) }
            context.delete(location)
        }
        try context.save()
    }
}
