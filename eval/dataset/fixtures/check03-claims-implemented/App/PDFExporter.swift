import UIKit

enum PDFExporter {
    static func render(_ text: String) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14)
            ]
            text.draw(in: pageRect.insetBy(dx: 36, dy: 36),
                      withAttributes: attributes)
        }
    }
}
