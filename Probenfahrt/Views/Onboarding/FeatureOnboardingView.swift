import SwiftUI

/// Short swipeable feature tour, shown once automatically after joining
/// (see RootTabView) and replayable any time from Einstellungen → Über.
/// Always skippable — "Überspringen" is reachable from every page, not just
/// the last one.
struct FeatureOnboardingView: View {
    let accountKind: AccountKind
    let onFinish: () -> Void

    @State private var selection = 0

    private var pages: [OnboardingPage] {
        var result: [OnboardingPage] = [
            OnboardingPage(
                symbolName: "hand.wave.fill",
                title: "Willkommen bei Probenfahrt",
                text: "Ein kurzer Überblick, bevor es losgeht."
            )
        ]
        if accountKind == .labTeam {
            result.append(OnboardingPage(
                symbolName: "list.bullet.clipboard",
                title: "Umfragen",
                text: "Trag dich für Fahrten ein — die Umfrage gilt immer für die nächsten zwei Kalenderwochen (Mo–Do)."
            ))
            result.append(OnboardingPage(
                symbolName: "calendar",
                title: "Kalender",
                text: "Alle eingetragenen Fahrten auf einen Blick, automatisch aus den Umfragen erzeugt."
            ))
        }
        result.append(OnboardingPage(
            symbolName: "cross.vial.fill",
            title: "Proben",
            text: accountKind == .pharmacy
                ? "Meldet hier täglich, ob ihr Proben für uns habt."
                : "Hier seht ihr, welche Apotheken und Briefkästen heute Proben für euch haben."
        ))
        if accountKind == .labTeam {
            result.append(OnboardingPage(
                symbolName: "bubble.left.and.bubble.right.fill",
                title: "Chat",
                text: "Für Absprachen im Team — als Gruppe oder unter vier Augen."
            ))
        }
        result.append(OnboardingPage(
            symbolName: "checkmark.circle.fill",
            title: "Los geht's",
            text: "Du findest diese Übersicht jederzeit wieder unter Einstellungen → Über."
        ))
        return result
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $selection) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    pageView(page, isLast: index == pages.count - 1)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button("Überspringen") {
                onFinish()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding()
        }
    }

    private func pageView(_ page: OnboardingPage, isLast: Bool) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: page.symbolName)
                .font(.system(size: 64))
                .foregroundStyle(PartnerBrand.yellow)
            Text(page.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(page.text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            if isLast {
                Button {
                    onFinish()
                } label: {
                    Text("Los geht's")
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(PartnerBrand.yellow)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            } else {
                Color.clear.frame(height: 60)
            }
        }
    }
}

private struct OnboardingPage {
    let symbolName: String
    let title: String
    let text: String
}
