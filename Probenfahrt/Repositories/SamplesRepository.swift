import Foundation
import SwiftData

@MainActor
protocol SamplesRepository {
    func locations(groupID: UUID) async throws -> [SampleLocation]
    /// The location a pharmacy account manages itself, creating it on first
    /// use (also used by the DevMode "Proben (Test)" preview tab for a
    /// lab-team account, so it always has something to toggle).
    func findOrCreateLocation(ownerUserID: UUID, groupID: UUID, name: String) async throws -> SampleLocation
    func setHasSamples(_ hasSamples: Bool, locationID: UUID) async throws
    /// Cleans up a location created via `findOrCreateLocation` once it's no
    /// longer needed — e.g. when a DevMode pharmacy-preview toggle (see
    /// SettingsView) is switched back off, so the preview doesn't leave a
    /// permanent, team-visible entry under the tester's real name.
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

    func setHasSamples(_ hasSamples: Bool, locationID: UUID) async throws {
        guard let location = try context.fetch(FetchDescriptor<SampleLocation>(predicate: #Predicate<SampleLocation> {
            $0.id == locationID
        })).first else { return }
        location.hasSamples = hasSamples
        location.updatedAt = .now
        try context.save()
    }

    func deleteLocationIfOwned(by ownerUserID: UUID) async throws {
        let owned = try context.fetch(FetchDescriptor<SampleLocation>(predicate: #Predicate<SampleLocation> {
            $0.ownerUserID == ownerUserID
        }))
        guard !owned.isEmpty else { return }
        owned.forEach { context.delete($0) }
        try context.save()
    }
}
