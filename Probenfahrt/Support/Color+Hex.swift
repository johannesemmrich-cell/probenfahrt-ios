import SwiftUI

extension Color {
    init(hex hexString: String) {
        let hex = UInt32(hexString.trimmingCharacters(in: .init(charactersIn: "#")), radix: 16) ?? 0x000000
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
