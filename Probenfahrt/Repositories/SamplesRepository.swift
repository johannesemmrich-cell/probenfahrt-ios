import Foundation
import SwiftData

@MainActor
protocol SamplesRepository {
    func locations(groupID: UUID) async throws -> [SampleLocation]
    /// Simple simulated access-code check for the Proben tab gate.
    /// TODO(Backlog #1): replace with real code-based access control/provisioning.
    func verifyAccessCode(_ code: String) -> Bool
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

    func verifyAccessCode(_ code: String) -> Bool {
        code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == MockDataSeeder.samplesAccessCode.lowercased()
    }
}
