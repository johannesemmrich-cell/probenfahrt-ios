import Foundation
import SwiftData

/// One Mon–Thu day a group can drive samples to/from the lab. `date` is always
/// normalized to the start of day (see `Calendar.startOfDay`) so equality/range
/// comparisons don't drift on time-of-day.
@Model
final class SurveyDay {
    var id: UUID = UUID()
    var date: Date = Date.now
    var groupID: UUID?
    var isLocked: Bool = false
    var lockReason: String?

    init(
        id: UUID = UUID(),
        date: Date,
        groupID: UUID?,
        isLocked: Bool = false,
        lockReason: String? = nil
    ) {
        self.id = id
        self.date = date
        self.groupID = groupID
        self.isLocked = isLocked
        self.lockReason = lockReason
    }
}
