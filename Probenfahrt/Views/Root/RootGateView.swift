import SwiftUI

struct RootGateView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        if session.isOnboarded {
            RootTabView()
        } else {
            OnboardingContainerView()
        }
    }
}
