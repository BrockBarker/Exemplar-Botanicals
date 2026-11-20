import SwiftUI
import PhotosUI
import ImageIO
import UIKit

/// Downsized copies of journal photos, decoded once and kept in memory, so grids and lists
/// don't decode full-size images on every redraw.
enum PhotoThumbnails {
    enum Size: CGFloat {
        /// Grid tiles and list rows.
        case small = 360
        /// Full screen. Journal photos are stored at 1600 px, so this is the whole photo.
        case large = 1600
    }

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 80 * 1024 * 1024
        return cache
    }()

    /// Changes when the photo is replaced, so a new photo never shows a stale thumbnail.
    static func key(_ entry: JournalEntry, _ size: Size) -> String {
        "\(entry.id.uuidString)|\(entry.photoAdded?.timeIntervalSince1970 ?? 0)|\(Int(size.rawValue))"
    }

    static func cached(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func store(_ image: UIImage, for key: String) {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        cache.setObject(image, forKey: key as NSString, cost: Int(pixels * 4))
    }

    /// Decodes straight to the target size with ImageIO, which is much cheaper than
    /// UIImage(data:) followed by a resize.
    static func decode(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// A journal entry's photo. Shows a soft placeholder while it loads; the caller sets the frame.
struct JournalPhotoView: View {
    let entry: JournalEntry
    var size: PhotoThumbnails.Size = .small
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    init(entry: JournalEntry, size: PhotoThumbnails.Size = .small, contentMode: ContentMode = .fill) {
        self.entry = entry
        self.size = size
        self.contentMode = contentMode
    }

    var body: some View {
        let key = PhotoThumbnails.key(entry, size)
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle()
                    .fill(Color(.tertiarySystemFill))
            }
        }
        .task(id: key) { await load(key) }
        .accessibilityElement()
        .accessibilityLabel("Photo")
    }

    private func load(_ key: String) async {
        if let hit = PhotoThumbnails.cached(key) {
            image = hit
            return
        }
        guard let data = entry.photo else {
            image = nil
            return
        }
        let maxPixel = size.rawValue
        let decoded = await Task.detached(priority: .userInitiated) {
            PhotoThumbnails.decode(data, maxPixel: maxPixel)
        }.value
        guard !Task.isCancelled else { return }
        if let decoded = decoded { PhotoThumbnails.store(decoded, for: key) }
        image = decoded
    }
}

/// A square tile for photo grids, with the day in the corner.
struct PhotoTile: View {
    let entry: JournalEntry
    var label: String?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { JournalPhotoView(entry: entry) }
            .overlay(alignment: .bottomLeading) {
                if let label = label {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// A full-screen photo you can pinch or double-tap to zoom, and drag around while zoomed.
struct ZoomablePhoto: View {
    let entry: JournalEntry

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    init(entry: JournalEntry) {
        self.entry = entry
    }

    var body: some View {
        JournalPhotoView(entry: entry, size: .large, contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = min(5, max(1, baseScale * value.magnification))
                    }
                    .onEnded { _ in
                        baseScale = scale
                        if scale <= 1.01 { reset() }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: baseOffset.width + value.translation.width,
                            height: baseOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in baseOffset = offset },
                including: scale > 1 ? .all : .none
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if scale > 1 {
                        reset()
                    } else {
                        scale = 2.5
                        baseScale = 2.5
                    }
                }
            }
            .clipped()
    }

    private func reset() {
        scale = 1
        baseScale = 1
        offset = .zero
        baseOffset = .zero
    }
}

/// "Take photo" and "Choose photo" buttons. Hands back the image and, for library photos that
/// have it, the day the photo was taken.
struct PhotoSourceButtons: View {
    let chooseTitle: String
    let onPick: (UIImage, Date?) -> Void

    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var failed = false

    init(chooseTitle: String = "Choose photo", onPick: @escaping (UIImage, Date?) -> Void) {
        self.chooseTitle = chooseTitle
        self.onPick = onPick
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(chooseTitle, systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if failed {
                Text("Couldn't open that photo. Try another one.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(image: $cameraImage)
                .ignoresSafeArea()
        }
        .onChange(of: cameraImage) { _, image in
            guard let image = image else { return }
            failed = false
            onPick(image, Date())
            cameraImage = nil
        }
        .onChange(of: pickerItem) { _, item in
            guard let item = item else { return }
            Task { await load(item) }
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            failed = true
            return
        }
        failed = false
        onPick(image, ImagePrep.dateTaken(data))
    }
}
