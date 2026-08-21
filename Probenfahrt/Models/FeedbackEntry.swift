import Foundation
import SwiftData
import SwiftUI

/// A 👎-feedback report submitted while Dev Mode is active (see DevModeStore),
/// tied to whatever screen/feature/element it was raised from.
@Model
final class FeedbackEntry {
    var id: UUID = UUID()
    var timestamp: Date = Date.now
    var screenContext: String = ""
    var featureContext: String = ""
    var elementContext: String = ""
    var notes: String = ""
    var priorityRawValue: String = FeedbackPriority.medium.rawValue
    var isResolved: Bool = false

    var priority: FeedbackPriority {
        get { FeedbackPriority(rawValue: priorityRawValue) ?? .medium }
        set { priorityRawValue = newValue.rawValue }
    }

    init(
        screenContext: String,
        featureContext: String,
        elementContext: String,
        notes: String,
        priority: FeedbackPriority
    ) {
        self.id = UUID()
        self.timestamp = .now
        self.screenContext = screenContext
        self.featureContext = featureContext
        self.elementContext = elementContext
        self.notes = notes
        self.priorityRawValue = priority.rawValue
        self.isResolved = false
    }
}

enum FeedbackPriority: String, Codable, CaseIterable {
    case urgent = "Dringend"
    case high = "Hoch"
    case medium = "Mittel"
    case low = "Niedrig"
    case testing = "Test"

    var emoji: String {
        switch self {
        case .urgent: return "🔴"
        case .high: return "🟠"
        case .medium: return "🟡"
        case .low: return "🔵"
        case .testing: return "🟣"
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .urgent: return Color(red: 0.6, green: 0, blue: 0)
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        case .testing: return .purple
        }
    }
}

@Model
final class DevTodoItem {
    var id: UUID = UUID()
    var title: String = ""
    var isCompleted: Bool = false
    var createdAt: Date = Date.now

    init(title: String) {
        self.id = UUID()
        self.title = title
        self.isCompleted = false
        self.createdAt = .now
    }
}

/// "In Arbeit" (currently-being-tested) marker for a DevTodoItem — kept in
/// UserDefaults rather than the model since it's a per-device UI state, not
/// data that should sync/export with the rest of the To-Do.
struct InProgressStore {
    private static let key = "com.johannesemmrich.probenfahrt.devTodoInProgressIDs"

    static var inProgressIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: key) }
    }

    static func isInProgress(_ id: UUID) -> Bool {
        inProgressIDs.contains(id.uuidString)
    }

    static func setInProgress(_ id: UUID, _ value: Bool) {
        var ids = inProgressIDs
        if value { ids.insert(id.uuidString) } else { ids.remove(id.uuidString) }
        inProgressIDs = ids
    }
}
