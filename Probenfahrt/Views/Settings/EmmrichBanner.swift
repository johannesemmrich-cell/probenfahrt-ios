import SwiftUI

/// Cross-promo banner shown at the bottom of Einstellungen, linking to the
/// Emmrich-Apps family site. Fixed brand colors — identical across all
/// Emmrich apps (Sunwake/Dresslyst/Restock), never adapted to this app's
/// own color world.
enum EmmrichBrand {
    static let gradient = LinearGradient(
        colors: [Color(hex: "2A2118"), Color(hex: "3A2E1E")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let border = Color(hex: "A98E5B").opacity(0.45)
    static let brass = Color(hex: "A98E5B")
    static let text = Color(hex: "EDE2CC")
    static let website = URL(string: "https://emmrich-business.com")!
}

struct EmmrichBanner: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(EmmrichBrand.website)
        } label: {
            HStack(spacing: 12) {
                // Frei schwebendes E aus 3 Balken, mittlerer 68 % Breite
                VStack(alignment: .leading, spacing: 0) {
                    bar(widthFraction: 1)
                    Spacer(minLength: 0)
                    bar(widthFraction: 0.68)
                    Spacer(minLength: 0)
                    bar(widthFraction: 1)
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Emmrich Apps")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(EmmrichBrand.text)
                    Text("Dresslyst · Restock · Sunwake · Probenfahrt")
                        .font(.system(size: 11))
                        .foregroundStyle(EmmrichBrand.brass)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EmmrichBrand.brass)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(EmmrichBrand.gradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(EmmrichBrand.border, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private func bar(widthFraction: CGFloat) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(EmmrichBrand.brass)
                .frame(width: geo.size.width * widthFraction)
        }
        .frame(height: 4.8)
    }
}
