import SwiftUI

/// One past day's summary row inside a PastSamplesView week block — tap
/// through to SampleDayDetailView for the full with/without split.
struct SampleDayCard: View {
    let day: Date
    let locations: [SampleLocation]
    let reports: [SampleReport]

    private var withSamples: [SampleDayGrouping.Entry] {
        SampleDayGrouping.withSamples(locations: locations, reports: reports)
    }

    private var withoutSamples: [SampleDayGrouping.Entry] {
        SampleDayGrouping.withoutSamples(locations: locations, reports: reports)
    }

    var body: some View {
        NavigationLink {
            SampleDayDetailView(day: day, locations: locations, reports: reports)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month().locale(.app)))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(withSamples.count) mit Proben · \(withoutSamples.count) ohne Proben")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
