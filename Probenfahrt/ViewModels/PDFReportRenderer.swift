import UIKit

enum PDFReportRenderer {
    static func renderMonthlyReport(title: String, lines: [MonthlyReportGenerator.ReportLine]) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4 at 72dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { context in
            context.beginPage()

            let titleAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 20)]
            let titleString = title as NSString
            titleString.draw(at: CGPoint(x: 40, y: 40), withAttributes: titleAttributes)

            let bodyAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14)]
            var y: CGFloat = 90

            if lines.isEmpty {
                let text = "Keine Fahrten in diesem Monat." as NSString
                text.draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttributes)
            } else {
                for line in lines {
                    let unit = line.tripCount == 1 ? "Fahrt" : "Fahrten"
                    let text = "\(line.userName): \(line.tripCount) \(unit)" as NSString
                    text.draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttributes)
                    y += 24
                }
            }
        }
    }
}
