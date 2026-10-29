import QuickLookThumbnailing
import SwiftUI
import ZeigCore

/// A file's icon in lists: a Quick Look thumbnail for images, PDFs, text and other files Quick
/// Look can draw (like the Files app), and the `FileIcon` tile for folders, archives and
/// anything without a thumbnail.
///
/// Thumbnails are made in the background and kept in memory (`ThumbnailCache`), keyed by path
/// and modification date, so scrolling back doesn't redraw them.
public struct FileThumbnail: View {
    private let url: URL
    private let isDirectory: Bool
    private let format: ArchiveFormat?
    private let modified: Date
    @State private var image: CGImage?
    @Environment(\.displayScale) private var displayScale

    public static let size: CGFloat = 36

    public init(url: URL, isDirectory: Bool, format: ArchiveFormat?, modified: Date) {
        self.url = url
        self.isDirectory = isDirectory
        self.format = format
        self.modified = modified
    }

    /// Folders and archives keep Zeig's own tiles: their Quick Look thumbnails are generic.
    private var wantsThumbnail: Bool { !isDirectory && format == nil }

    public var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.size, height: Self.size)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.primary.opacity(0.1), lineWidth: 0.5))
            } else {
                FileIcon(isDirectory: isDirectory, format: format, fileName: url.lastPathComponent)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .task(id: "\(url.path)|\(modified.timeIntervalSince1970)") {
            guard wantsThumbnail else { return }
            image = await ThumbnailCache.shared.thumbnail(for: url, modified: modified, scale: displayScale)
        }
    }
}

/// Generated thumbnails, in memory only.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var images: [String: CGImage] = [:]
    /// Files Quick Look had no thumbnail for, so they aren't asked again.
    private var misses: Set<String> = []

    func thumbnail(for url: URL, modified: Date, scale: CGFloat) async -> CGImage? {
        let key = "\(url.path)|\(modified.timeIntervalSince1970)"
        if let image = images[key] { return image }
        if misses.contains(key) { return nil }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: FileThumbnail.size, height: FileThumbnail.size),
            scale: scale,
            representationTypes: .thumbnail
        )
        let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
        if let image {
            if images.count > 400 { images.removeAll() }
            images[key] = image
        } else {
            misses.insert(key)
        }
        return image
    }
}
