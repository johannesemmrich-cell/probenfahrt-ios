import Foundation

/// TODO(Backlog #2): the only real gate; once auth lands, drop the
/// `adminPreview`/`devMode` override halves of this check entirely.
/// True for Haupt-Admin OR Vice-Admin (or either dev-only preview override)
/// — i.e. anyone with *some* admin access. Use `isFullAdmin` for the small
/// set of Haupt-Admin-only actions (Mitglieder entfernen, Kürzel ändern,
/// Vice-Admin ernennen/zurückstufen).
func isEffectiveAdmin(user: User, adminPreview: AdminPreviewStore, devMode: DevModeStore) -> Bool {
    user.role == .admin || user.role == .viceAdmin || adminPreview.isEnabled || devMode.isAdminPreviewActive
}

/// True only for full Haupt-Admin rights (or either preview override).
func isFullAdmin(user: User, adminPreview: AdminPreviewStore, devMode: DevModeStore) -> Bool {
    user.role == .admin || adminPreview.isEnabled || devMode.isAdminPreviewActive
}

/// True only for the two preview/override flags — NOT a real Haupt-Admin
/// role. This is "someone is poking at the app with a dev/preview override
/// active", as opposed to "a real team Haupt-Admin". Gates a couple of
/// escape hatches (removing the group's last Haupt-Admin, stripping an
/// existing Haupt-Admin's role) that even a real Haupt-Admin can't do —
/// those stay blocked so a real admin can't accidentally leave the group
/// with zero manageable admins; the developer explicitly bypassing via a
/// preview override is a different, deliberate situation.
func isDeveloperOverride(adminPreview: AdminPreviewStore, devMode: DevModeStore) -> Bool {
    adminPreview.isEnabled || devMode.isAdminPreviewActive
}

/// Once a survey day's date is in the past, only an admin (either tier) may
/// still sign people in/out or lock/unlock it — everyone else gets a
/// read-only view.
func canEditSurveyDay(_ day: SurveyDay, user: User, adminPreview: AdminPreviewStore, devMode: DevModeStore, calendar: Calendar = .current) -> Bool {
    isEffectiveAdmin(user: user, adminPreview: adminPreview, devMode: devMode)
        || calendar.startOfDay(for: day.date) >= calendar.startOfDay(for: .now)
}

/// The simple self Eintragen/Austragen quick-toggle only makes sense for a
/// day that isn't in the past — once a day is past, an admin's editing
/// happens via the full "Verwalten" (manage-anyone) screen instead (see
/// SurveyDayCard/SurveyDayDetailView), not this one-tap self-toggle.
func shouldShowQuickToggle(for day: SurveyDay, user: User, adminPreview: AdminPreviewStore, devMode: DevModeStore, calendar: Calendar = .current) -> Bool {
    guard canEditSurveyDay(day, user: user, adminPreview: adminPreview, devMode: devMode, calendar: calendar) else { return false }
    let isPast = calendar.startOfDay(for: day.date) < calendar.startOfDay(for: .now)
    return !(isEffectiveAdmin(user: user, adminPreview: adminPreview, devMode: devMode) && isPast)
}
