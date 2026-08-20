import SwiftUI
import SwiftData

/// TODO(Backlog #1): simple simulated code check — replace with real
/// code-based access control/provisioning.
struct SamplesGateView: View {
    let currentUser: User

    @Environment(\.modelContext) private var modelContext
    @Environment(SamplesAccessStore.self) private var samplesAccess
    @State private var code = ""
    @State private var errorMessage: String?

    private var samplesRepository: SamplesRepository { SwiftDataSamplesRepository(context: modelContext) }

    var body: some View {
        NavigationStack {
            if samplesAccess.isUnlocked {
                SamplesListView(currentUser: currentUser)
            } else {
                gateContent
                    .navigationTitle("Proben")
            }
        }
    }

    private var gateContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Zugriffscode erforderlich")
                .font(.title3.bold())

            Text("Dieser Bereich ist gesondert geschützt. Gib den Freischaltcode ein.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Freischaltcode", text: $code)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }

            Button {
                unlock()
            } label: {
                Text("Freischalten").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding(24)
    }

    private func unlock() {
        if samplesRepository.verifyAccessCode(code) {
            errorMessage = nil
            samplesAccess.isUnlocked = true
        } else {
            errorMessage = "Falscher Code. Bitte erneut versuchen."
        }
    }
}
