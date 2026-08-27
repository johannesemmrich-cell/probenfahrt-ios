import SwiftUI

/// Full with/without split for one past day — the same layout as
/// SamplesListView's today view, reached by tapping a SampleDayCard in
/// PastSamplesView.
struct SampleDayDetailView: View {
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
        List {
            if !withSamples.isEmpty {
                Section("Proben vorhanden (\(withSamples.count))") {
                    ForEach(withSamples) { entry in
                        SampleLocationRow(entry: entry, hasSamples: true)
                    }
                }
            }
            if !withoutSamples.isEmpty {
                Section("Keine Proben (\(withoutSamples.count))") {
                    ForEach(withoutSamples) { entry in
                        SampleLocationRow(entry: entry, hasSamples: false)
                    }
                }
            }
        }
        .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month().locale(.app)))
        .navigationBarTitleDisplayMode(.inline)
    }
}
