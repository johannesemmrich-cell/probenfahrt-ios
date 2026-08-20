import SwiftUI

struct WeekListView: View {
    let referenceDate: Date
    let rows: [SurveyDayRow]
    let users: [User]

    private let calendar = Calendar.current

    private var weekDates: [Date] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return [] }
        var dates: [Date] = []
        var cursor = weekInterval.start
        while cursor < weekInterval.end {
            let weekday = calendar.component(.weekday, from: cursor)
            if (2...5).contains(weekday) {
                dates.append(cursor)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return dates
    }

    private func row(for date: Date) -> SurveyDayRow? {
        rows.first { calendar.isDate($0.day.date, inSameDayAs: date) }
    }

    private func names(for date: Date) -> [String] {
        guard let row = row(for: date) else { return [] }
        return row.entries
            .compactMap { entry in users.first { $0.id == entry.userID }?.name }
            .sorted()
    }

    var body: some View {
        List(weekDates, id: \.self) { date in
            VStack(alignment: .leading, spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.wide).day().month().locale(.app)))
                    .font(.headline)

                if row(for: date)?.day.isLocked == true {
                    Label("Gesperrt", systemImage: "lock.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    let dayNames = names(for: date)
                    if dayNames.isEmpty {
                        Text("Niemand eingetragen")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(dayNames.joined(separator: ", "))
                            .font(.subheadline)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.plain)
    }
}
