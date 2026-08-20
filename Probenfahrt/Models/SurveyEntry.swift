import Foundation
import SwiftData

/// A single user's sign-up for a `SurveyDay`. Existence of a row = signed in;
/// deleting the row = signed out. References `SurveyDay`/`User` by id rather
/// than a SwiftData relationship, so a future networked repository can return
/// the same shape (plain foreign keys) without changing call sites.
@Model
final class SurveyEntry {
    var id: UUID = UUID()
    var surveyDayID: UUID?
    var userID: UUID?
    var createdAt: Date = Date.now

    init(
        id: UUID = UUID(),
        surveyDayID: UUID?,
        userID: UUID?,
        createdAt: Date = .now
    ) {
        self.id = id
        self.surveyDayID = surveyDayID
        self.userID = userID
        self.createdAt = createdAt
    }
}
