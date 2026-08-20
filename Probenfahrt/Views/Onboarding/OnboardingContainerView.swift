import SwiftUI
import SwiftData

struct OnboardingContainerView: View {
    private enum Step {
        case identity
        case joinCode
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(SessionStore.self) private var session

    @State private var name = ""
    @State private var abbreviation = ""
    @State private var joinCode = ""
    @State private var step: Step = .identity
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    private var userRepository: UserRepository { SwiftDataUserRepository(context: modelContext) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                switch step {
                case .identity:
                    identityStep
                case .joinCode:
                    joinCodeStep
                }
            }
            .padding(24)
            .navigationTitle("Willkommen")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var identityStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Wie heißt du?")
                .font(.title2.bold())
            Text("Name und ein eindeutiges Kürzel, unter dem dich das Team wiedererkennt.")
                .foregroundStyle(.secondary)

            TextField("Vollständiger Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)

            TextField("Kürzel (z.B. JE)", text: $abbreviation)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            errorText

            Spacer()

            Button {
                continueFromIdentity()
            } label: {
                Text("Weiter").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || abbreviation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var joinCodeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gruppen-Code")
                .font(.title2.bold())
            Text("Gib den Beitrittscode für eure Labor-Gruppe ein.")
                .foregroundStyle(.secondary)

            TextField("Beitrittscode", text: $joinCode)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            errorText

            Spacer()

            Button {
                Task { await joinGroup() }
            } label: {
                if isSubmitting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Beitreten").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)

            Button("Zurück") {
                step = .identity
                errorMessage = nil
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var errorText: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func continueFromIdentity() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAbbreviation = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedAbbreviation.isEmpty else { return }
        name = trimmedName
        abbreviation = trimmedAbbreviation
        errorMessage = nil
        step = .joinCode
    }

    private func joinGroup() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            guard let group = try await userRepository.resolveGroup(joinCode: joinCode) else {
                errorMessage = "Unbekannter Code. Bitte beim Team nachfragen."
                return
            }
            // Only one demo group exists right now, so this uniqueness check is
            // effectively global — but it's already scoped by groupID, so it
            // stays correct once a second group exists.
            if try await userRepository.isAbbreviationTaken(abbreviation, inGroup: group.id) {
                errorMessage = "Dieses Kürzel ist in dieser Gruppe schon vergeben."
                step = .identity
                return
            }
            let user = try await userRepository.createUser(name: name, abbreviation: abbreviation, groupID: group.id)
            session.setCurrentUser(id: user.id)
        } catch {
            errorMessage = "Etwas ist schiefgelaufen. Bitte erneut versuchen."
        }
    }
}
