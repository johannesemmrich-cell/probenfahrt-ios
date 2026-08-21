import SwiftUI
import SwiftData

// MARK: — Unlock Sheet

struct DeveloperUnlockSheet: View {
    @Binding var isPresented: Bool
    @Environment(DevModeStore.self) private var devMode

    @State private var password = ""
    @State private var error = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(devMode.isActive
                         ? "Passwort eingeben, um den Entwicklermodus zu deaktivieren."
                         : "Passwort eingeben, um den Entwicklermodus zu aktivieren.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    SecureField("Passwort", text: $password)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                if !error.isEmpty {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Entwicklermodus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bestätigen") { handleSubmit() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.fraction(0.4)])
    }

    private func handleSubmit() {
        guard DevPassword.matches(password) else {
            error = "Falsches Passwort."
            password = ""
            return
        }
        devMode.isActive.toggle()
        isPresented = false
    }
}

// MARK: — Developer Mode Main View

struct DeveloperModeView: View {
    @Environment(DevModeStore.self) private var devMode
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FeedbackEntry.timestamp, order: .reverse) private var feedbackEntries: [FeedbackEntry]
    @Query(sort: \DevTodoItem.createdAt, order: .forward) private var todoItems: [DevTodoItem]

    @State private var showAddTodo = false
    @State private var showExitConfirm = false
    @State private var priorityFilter: FeedbackPriority?
    @State private var showOnlyOpen = true

    private var filteredFeedback: [FeedbackEntry] {
        feedbackEntries.filter { entry in
            (priorityFilter == nil || entry.priority == priorityFilter) &&
            (showOnlyOpen ? !entry.isResolved : entry.isResolved)
        }
    }

    var body: some View {
        List {
            Section {
                Label("Entwicklermodus ist aktiv", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            }

            let inProgressItems = todoItems.filter { InProgressStore.isInProgress($0.id) && !$0.isCompleted }
            let openItems = todoItems.filter { !InProgressStore.isInProgress($0.id) && !$0.isCompleted }
            let doneItems = todoItems.filter { $0.isCompleted }

            if !inProgressItems.isEmpty {
                Section {
                    ForEach(inProgressItems) { item in
                        DevTodoRow(item: item)
                    }
                } header: {
                    Label("In Arbeit", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                }
            }

            Section("To-Do (\(openItems.count))") {
                if todoItems.isEmpty {
                    Text("Noch keine Einträge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if openItems.isEmpty {
                    Text("Alles in Arbeit oder erledigt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(openItems) { item in
                    DevTodoRow(item: item)
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(openItems[index])
                    }
                }
                Button {
                    showAddTodo = true
                } label: {
                    Label("Neues To-Do", systemImage: "plus.circle")
                }
            }

            if !doneItems.isEmpty {
                Section("Erledigt (\(doneItems.count))") {
                    ForEach(doneItems) { item in
                        DevTodoRow(item: item)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(doneItems[index])
                        }
                    }
                }
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FeedbackFilterChip(
                            label: "Alle",
                            color: .secondary,
                            isSelected: priorityFilter == nil
                        ) { priorityFilter = nil }

                        ForEach(FeedbackPriority.allCases, id: \.self) { p in
                            FeedbackFilterChip(
                                label: "\(p.emoji) \(p.rawValue)",
                                color: p.swiftUIColor,
                                isSelected: priorityFilter == p
                            ) {
                                priorityFilter = priorityFilter == p ? nil : p
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

                HStack {
                    Button {
                        withAnimation(.spring(duration: 0.2)) { showOnlyOpen = true }
                    } label: {
                        Label("Offen (\(feedbackEntries.filter { !$0.isResolved }.count))", systemImage: "circle")
                            .font(.caption.weight(showOnlyOpen ? .semibold : .regular))
                            .foregroundStyle(showOnlyOpen ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        withAnimation(.spring(duration: 0.2)) { showOnlyOpen = false }
                    } label: {
                        Label("Erledigt (\(feedbackEntries.filter { $0.isResolved }.count))", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(!showOnlyOpen ? .semibold : .regular))
                            .foregroundStyle(!showOnlyOpen ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Feedback (\(filteredFeedback.count))") {
                if filteredFeedback.isEmpty {
                    Text(feedbackEntries.isEmpty
                         ? "Noch kein Feedback. Tippe auf 👎 während der Entwicklermodus aktiv ist."
                         : "Kein Feedback für diesen Filter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredFeedback) { entry in
                        HStack(spacing: 12) {
                            Button {
                                withAnimation { entry.isResolved.toggle() }
                            } label: {
                                Image(systemName: entry.isResolved ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(entry.isResolved ? .green : .secondary)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: FeedbackEntryDetailView(entry: entry)) {
                                FeedbackEntryRow(entry: entry)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let toDelete = offsets.map { filteredFeedback[$0] }
                        toDelete.forEach { modelContext.delete($0) }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showExitConfirm = true
                } label: {
                    Label("Entwicklermodus beenden", systemImage: "xmark.shield")
                }
            } footer: {
                Text("Feedback, To-Dos und alle anderen Daten bleiben erhalten.")
                    .font(.caption)
            }
        }
        .navigationTitle("Entwicklermodus")
        .listStyle(.insetGrouped)
        .toolbar {
            if !feedbackEntries.isEmpty || !todoItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showAddTodo) {
            AddDevTodoSheet(isPresented: $showAddTodo)
        }
        .confirmationDialog(
            "Entwicklermodus beenden?",
            isPresented: $showExitConfirm,
            titleVisibility: .visible
        ) {
            Button("Beenden", role: .destructive) { devMode.isActive = false }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle Feedback-Einträge, To-Dos und Einstellungen bleiben erhalten.")
        }
    }
}

private struct FeedbackFilterChip: View {
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected ? color.opacity(0.15) : Color(.secondarySystemBackground))
                        .overlay(Capsule().strokeBorder(isSelected ? color.opacity(0.4) : Color.clear, lineWidth: 1))
                )
                .foregroundStyle(isSelected ? color : .secondary)
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.18), value: isSelected)
    }
}

// MARK: — Dev Todo Row

private struct DevTodoRow: View {
    @Bindable var item: DevTodoItem
    @State private var inProgress: Bool

    init(item: DevTodoItem) {
        self.item = item
        self._inProgress = State(initialValue: InProgressStore.isInProgress(item.id))
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if item.isCompleted {
                    item.isCompleted = false
                } else {
                    item.isCompleted = true
                    inProgress = false
                    InProgressStore.setInProgress(item.id, false)
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : (inProgress ? "arrow.triangle.2.circlepath.circle.fill" : "circle"))
                    .foregroundStyle(item.isCompleted ? .green : (inProgress ? .orange : .secondary))
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                if inProgress && !item.isCompleted {
                    Text("In Arbeit")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            if !item.isCompleted {
                Button {
                    inProgress.toggle()
                    InProgressStore.setInProgress(item.id, inProgress)
                } label: {
                    Text(inProgress ? "Pause" : "Testen")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(inProgress ? Color.orange.opacity(0.15) : Color.blue.opacity(0.12))
                        )
                        .foregroundStyle(inProgress ? .orange : .blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: — Add Todo Sheet

struct AddDevTodoSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Aufgabe") {
                    TextField("Titel", text: $title)
                        .focused($focused)
                }
            }
            .navigationTitle("Neues To-Do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hinzufügen") {
                        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        modelContext.insert(DevTodoItem(title: title.trimmingCharacters(in: .whitespaces)))
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.fraction(0.35)])
    }
}

struct FeedbackEntryRow: View {
    let entry: FeedbackEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.screenContext)
                    .font(.caption.weight(.semibold))
                Text("›")
                    .foregroundStyle(.secondary)
                Text(entry.featureContext)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.priority.emoji)
            }
            if !entry.notes.isEmpty {
                Text(entry.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(entry.timestamp, format: .dateTime.day().month().hour().minute())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct FeedbackEntryDetailView: View {
    @Bindable var entry: FeedbackEntry

    var body: some View {
        Form {
            Section("Kontext") {
                LabeledContent("Bildschirm", value: entry.screenContext)
                LabeledContent("Feature", value: entry.featureContext)
                LabeledContent("Element", value: entry.elementContext)
                LabeledContent("Zeit", value: entry.timestamp.formatted(.dateTime))
            }

            Section("Notizen") {
                TextEditor(text: $entry.notes)
                    .frame(minHeight: 80)
            }

            Section("Priorität") {
                Picker("Priorität", selection: $entry.priority) {
                    ForEach(FeedbackPriority.allCases, id: \.self) { p in
                        Text("\(p.emoji) \(p.rawValue)").tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: — Feedback collection UI (thumbs down overlay)

struct DeveloperFeedbackButton: View {
    let screen: String
    let feature: String
    let element: String
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Image(systemName: "hand.thumbsdown.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(5)
                .background(Circle().fill(Color.red.opacity(0.7)))
        }
        .sheet(isPresented: $showSheet) {
            FeedbackSubmitSheet(screen: screen, feature: feature, element: element)
        }
    }
}

struct FeedbackSubmitSheet: View {
    let screen: String
    let feature: String
    let element: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var notes = ""
    @State private var priority: FeedbackPriority = .medium
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Kontext") {
                    LabeledContent("Bildschirm", value: screen)
                    LabeledContent("Feature", value: feature)
                    LabeledContent("Element", value: element)
                }

                Section("Notizen") {
                    TextEditor(text: $notes)
                        .focused($focused)
                        .frame(minHeight: 80)
                }

                Section("Priorität") {
                    Picker("Priorität", selection: $priority) {
                        ForEach(FeedbackPriority.allCases, id: \.self) { p in
                            Text("\(p.emoji) \(p.rawValue)").tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Feedback senden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Speichern") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { focused = true }
        }
    }

    private func save() {
        let entry = FeedbackEntry(
            screenContext: screen,
            featureContext: feature,
            elementContext: element,
            notes: notes,
            priority: priority
        )
        modelContext.insert(entry)
        dismiss()
    }
}

// MARK: — ViewModifier for developer feedback overlays

struct DeveloperFeedbackOverlay: ViewModifier {
    let isActive: Bool
    let screen: String
    let feature: String
    let element: String

    func body(content: Content) -> some View {
        if isActive {
            content.overlay(alignment: .topTrailing) {
                DeveloperFeedbackButton(screen: screen, feature: feature, element: element)
                    .padding(4)
            }
        } else {
            content
        }
    }
}

extension View {
    func developerFeedbackOverlay(isActive: Bool, screen: String, feature: String, element: String) -> some View {
        modifier(DeveloperFeedbackOverlay(isActive: isActive, screen: screen, feature: feature, element: element))
    }
}
