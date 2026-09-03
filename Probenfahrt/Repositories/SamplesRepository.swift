import Foundation

@MainActor
protocol SamplesRepository {
    func locations(groupID: UUID) async throws -> [SampleLocation]
    /// The location a pharmacy account manages itself, creating it on first
    /// use (also used by the DevMode "Proben (Test)" preview tab for a
    /// lab-team account, so it always has something to toggle).
    func findOrCreateLocation(ownerUserID: UUID, groupID: UUID, name: String) async throws -> SampleLocation
    /// Admin-created location with no owning user account at all. If
    /// `usesQRCheckIn`, it's meant for the QR-code web check-in path
    /// (BACKLOG #3) — identified by its `token`; otherwise it's a pharmacy
    /// the admin reports on behalf of manually (e.g. one that can't use the
    /// web check-in), which gets no QR code shown at all.
    func createLocation(groupID: UUID, name: String, address: String, usesQRCheckIn: Bool) async throws -> SampleLocation
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
    /// All reports for a group's locations within an arbitrary day range
    /// (`from`...`to`, inclusive) in a single query — used by
    /// PastSamplesView instead of querying day by day, which used to mean
    /// one network round-trip per day (up to 56 for its 8-week window).
    func reports(groupID: UUID, from: Date, to: Date) async throws -> [SampleReport]
    func setHasSamples(_ hasSamples: Bool, locationID: UUID, day: Date) async throws
    /// Cleans up a location created via `findOrCreateLocation` (and all of
    /// its reports) once it's no longer needed — e.g. when a DevMode
    /// pharmacy-preview toggle (see SettingsView) is switched back off, so
    /// the preview doesn't leave a permanent, team-visible entry under the
    /// tester's real name.
    func deleteLocationIfOwned(by ownerUserID: UUID) async throws
    /// Admin-triggered delete of a location and all of its reports (e.g.
    /// from "Apotheken verwalten") — `ownerUserID` must be passed through
    /// unchanged from the SampleLocation being deleted, since it's part of
    /// how the location's underlying record is identified.
    func deleteLocation(id: UUID, ownerUserID: UUID?) async throws
}
