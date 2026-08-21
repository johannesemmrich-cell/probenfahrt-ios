import SwiftUI

/// The "Fahrplan vom ... bis ..." section header shown above every Umfragen
/// week block — shared between the 2 "aktuell" blocks (SurveysView) and the
/// grouped past weeks (PastSurveysView), so both render identically.
struct FahrplanHeader: View {
    let block: SurveyWeekWindow.WeekBlock
    var isCurrent: Bool = false

    var body: some View {
        HStack {
            Text("Fahrplan vom \(block.weekStart.formatted(.dateTime.weekday(.wide).day().month().locale(.app))) bis \(block.weekEnd.formatted(.dateTime.weekday(.wide).day().month().locale(.app)))")
            if isCurrent {
                Spacer()
                Text("Aktuell")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
            }
        }
    }
}
