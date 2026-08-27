import SwiftUI

/// One Apotheke/Labor's report row — shared between SamplesListView
/// (today) and SampleDayDetailView (a past day), so both look identical.
struct SampleLocationRow: View {
    let entry: SampleDayGrouping.Entry
    let hasSamples: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.location.name).font(.headline)
                Text(entry.location.address).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if hasSamples {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(entry.report.reportedAt.formatted(.dateTime.weekday(.wide).day().month().locale(.app)))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Label(
                        entry.report.statusNote.isEmpty ? "Proben vorhanden" : entry.report.statusNote,
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                }
            } else {
                Text("Keine Proben")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary))
            }
        }
        .padding(.vertical, 2)
    }
}
