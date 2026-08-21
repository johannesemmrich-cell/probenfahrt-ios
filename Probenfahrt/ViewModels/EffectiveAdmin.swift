import Foundation

/// TODO(Backlog #2): the only real gate; once auth lands, drop the `adminPreview`
/// half of this check entirely.
func isEffectiveAdmin(user: User, adminPreview: AdminPreviewStore) -> Bool {
    user.role == .admin || adminPreview.isEnabled
}

/// Once a survey day's date is in the past, only an admin may still sign
/// people in/out or lock/unlock it — everyone else gets a read-only view.
func canEditSurveyDay(_ day: SurveyDay, user: User, adminPreview: AdminPreviewStore, calendar: Calendar = .current) -> Bool {
    isEffectiveAdmin(user: user, adminPreview: adminPreview)
        || calendar.startOfDay(for: day.date) >= calendar.startOfDay(for: .now)
}

/// The simple self Eintragen/Austragen quick-toggle only makes sense for a
/// day that isn't in the past — once a day is past, an admin's editing
/// happens via the full "Verwalten" (manage-anyone) screen instead (see
/// SurveyDayCard/SurveyDayDetailView), not this one-tap self-toggle.
func shouldShowQuickToggle(for day: SurveyDay, user: User, adminPreview: AdminPreviewStore, calendar: Calendar = .current) -> Bool {
    guard canEditSurveyDay(day, user: user, adminPreview: adminPreview, calendar: calendar) else { return false }
    let isPast = calendar.startOfDay(for: day.date) < calendar.startOfDay(for: .now)
    return !(isEffectiveAdmin(user: user, adminPreview: adminPreview) && isPast)
}
