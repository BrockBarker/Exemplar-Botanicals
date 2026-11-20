import UIKit
import ImageIO

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

    /// For the journal and the progress galleries: long side 1600 px, big enough to zoom in on
    /// a leaf, around 300 KB.
    static func forJournal(_ image: UIImage) -> Data? {
        jpeg(image, maxDimension: 1600, quality: 0.75)
    }

    /// When a photo was taken, from its EXIF data. Cameras write local time with no zone, so
    /// it's read in the phone's time zone.
    static func dateTaken(_ data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = (exif[kCGImagePropertyExifDateTimeOriginal] ?? exif[kCGImagePropertyExifDateTimeDigitized]) as? String
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }
}
