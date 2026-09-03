import CoreImage.CIFilterBuiltins
import UIKit

/// Renders a QR code for a pharmacy's web check-in link (BACKLOG #3).
enum QRCodeGenerator {
    static func image(for string: String, scale: CGFloat = 10) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        // CoreImage's native output is only a few dozen pixels across — scale
        // up before rendering so it stays sharp when displayed/printed.
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
