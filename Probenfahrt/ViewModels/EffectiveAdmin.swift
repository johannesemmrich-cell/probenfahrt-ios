import Foundation

/// TODO(Backlog #4): the only real gate; once auth lands, drop the `adminPreview`
/// half of this check entirely.
func isEffectiveAdmin(user: User, adminPreview: AdminPreviewStore) -> Bool {
    user.role == .admin || adminPreview.isEnabled
}
