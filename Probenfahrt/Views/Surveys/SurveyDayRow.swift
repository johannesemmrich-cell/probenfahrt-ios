import Foundation

struct SurveyDayRow: Identifiable {
    let day: SurveyDay
    let entries: [SurveyEntry]
    var id: UUID { day.id }
}
