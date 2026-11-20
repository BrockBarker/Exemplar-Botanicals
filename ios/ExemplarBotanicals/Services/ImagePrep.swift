import UIKit

/// Shrinks photos before they leave the phone: the coach sees plenty at 1568 px, and a
/// smaller file uploads faster and costs less.
enum ImagePrep {
    static func jpeg(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// For the coach: long side 1568 px.
    static func forCoach(_ image: UIImage) -> Data? {
        jpeg(image, maxDimension: 1568, quality: 0.8)
    }

    /// For the journal: long side 800 px.
    static func thumbnail(_ image: UIImage) -> Data? {
        jpeg(image, maxDimension: 800, quality: 0.7)
    }
}
