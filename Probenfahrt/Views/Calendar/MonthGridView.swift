import SwiftUI

/// Classic 7-column month grid. Only Mon–Thu cells ever carry survey data —
/// Fri–Sun are shown (for a familiar calendar look) but always muted/empty.
struct MonthGridView: View {
    let referenceDate: Date
    let rows: [SurveyDayRow]
    let users: [User]

    private let calendar = Calendar.current
    private let weekdaySymbols = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    private var weeks: [[Date?]] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: referenceDate) else { return [] }
        let firstOfMonth = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth) // 1=Sun...7=Sat
        let mondayFirstOffset = (firstWeekday + 5) % 7 // Mon=0 ... Sun=6

        var days: [Date?] = Array(repeating: nil, count: mondayFirstOffset)
        var cursor = firstOfMonth
        while cursor < monthInterval.end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    private func row(for date: Date) -> SurveyDayRow? {
        rows.first { calendar.isDate($0.day.date, inSameDayAs: date) }
    }

    private func initials(for date: Date) -> [String] {
        guard let row = row(for: date) else { return [] }
        return row.entries.compactMap { entry in users.first { $0.id == entry.userID }?.abbreviation }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(weeks.indices, id: \.self) { weekIndex in
                HStack(spacing: 4) {
                    ForEach(weeks[weekIndex].indices, id: \.self) { dayIndex in
                        if let date = weeks[weekIndex][dayIndex] {
                            dayCell(date: date)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 52)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func dayCell(date: Date) -> some View {
        let weekday = calendar.component(.weekday, from: date)
        let isRelevantDay = (2...5).contains(weekday)
        let dayInitials = initials(for: date)
        let isLocked = row(for: date)?.day.isLocked ?? false

        VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: date))")
                .font(.subheadline)
                .foregroundStyle(isRelevantDay ? Color.primary : Color.secondary)

            if isRelevantDay {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                } else if !dayInitials.isEmpty {
                    Text(dayInitials.prefix(2).joined(separator: ","))
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(calendar.isDateInToday(date) ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
