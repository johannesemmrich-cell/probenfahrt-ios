import SwiftUI

/// The "Woche vom ... bis ..." section header shown above every week block
/// in PastSamplesView — same idea as Umfragen's FahrplanHeader.
struct SampleWeekHeader: View {
    let block: SampleWeekWindow.WeekBlock

    var body: some View {
        Text("Woche vom \(block.weekStart.formatted(.dateTime.day().month().locale(.app))) bis \(block.weekEnd.formatted(.dateTime.day().month().locale(.app)))")
    }
}
