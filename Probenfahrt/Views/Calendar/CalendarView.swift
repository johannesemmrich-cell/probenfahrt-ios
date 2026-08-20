import SwiftUI
import SwiftData

struct CalendarView: View {
    let currentUser: User

    private enum ViewMode: String, CaseIterable {
        case month = "Monat"
        case week = "Woche"
    }

    @Environment(\.modelContext) private var modelContext
    @State private var referenceDate = Calendar.current.startOfDay(for: .now)
    @State private var viewMode: ViewMode = .month
    @State private var rows: [SurveyDayRow] = []
    @State private var users: [User] = []

    private var surveyRepository: SurveyRepository { SwiftDataSurveyRepository(context: modelContext) }
    private var userRepository: UserRepository { SwiftDataUserRepository(context: modelContext) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Ansicht", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                navigationHeader

                if viewMode == .month {
                    MonthGridView(referenceDate: referenceDate, rows: rows, users: users)
                } else {
                    WeekListView(referenceDate: referenceDate, rows: rows, users: users)
                }

                Spacer()
            }
            .navigationTitle("Kalender")
            .task(id: referenceDate) { await load() }
        }
    }

    private var navigationHeader: some View {
        HStack {
            Button { shift(by: -1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(headerTitle).font(.headline)
            Spacer()
            Button { shift(by: 1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
    }

    private var headerTitle: String {
        switch viewMode {
        case .month:
            return referenceDate.formatted(.dateTime.month(.wide).year().locale(.app))
        case .week:
            return referenceDate.formatted(.dateTime.week().locale(.app))
        }
    }

    private func shift(by value: Int) {
        let component: Calendar.Component = viewMode == .month ? .month : .weekOfYear
        if let newDate = Calendar.current.date(byAdding: component, value: value, to: referenceDate) {
            referenceDate = newDate
        }
    }

    private func load() async {
        guard let groupID = currentUser.groupID else { return }
        do {
            users = try await userRepository.allUsers(inGroup: groupID)
            let calendar = Calendar.current
            let interval: DateInterval?
            switch viewMode {
            case .month:
                interval = calendar.dateInterval(of: .month, for: referenceDate)
            case .week:
                interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate)
            }
            guard let interval else { return }
            let days = try await surveyRepository.existingSurveyDays(from: interval.start, to: interval.end, groupID: groupID)
            var newRows: [SurveyDayRow] = []
            for day in days {
                let entries = try await surveyRepository.entries(forDayID: day.id)
                newRows.append(SurveyDayRow(day: day, entries: entries))
            }
            rows = newRows
        } catch {
            rows = []
        }
    }
}
