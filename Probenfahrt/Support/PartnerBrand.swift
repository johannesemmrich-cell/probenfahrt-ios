import SwiftUI

/// Brand color of the lab/pharmacy partner this app is primarily built
/// for — distinct from EmmrichBrand (Johannes' own cross-app identity in
/// the Settings footer, never adapted to a client's colors).
enum PartnerBrand {
    static let yellow = Color(hex: "FEF200")
}

/// The partner's square mark: a yellow square with a white right triangle
/// cut from the top-left corner (hypotenuse from top-right to bottom-left).
struct PartnerLogoMark: View {
    var cornerRadius: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PartnerBrand.yellow
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(.white)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
