import AppKit
import ImageIO

/// Fast, cached, off-main-thread downsampling. Never decodes a full 5K screenshot just to show 200pt.
enum Thumbnails {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 256 << 20 // ~256 MB of decoded pixels
        return cache
    }()

    private static var usedSizes: Set<Int> = []

    private static func key(_ url: URL, _ maxPixel: Int) -> NSString { "\(maxPixel)|\(url.path)" as NSString }

    static func image(for url: URL, maxPixel: Int) async -> NSImage? {
        let key = key(url, maxPixel)
        usedSizes.insert(maxPixel)
        if let hit = cache.object(forKey: key) { return hit }
        guard let cg = await Task.detached(priority: .userInitiated, operation: { decode(url, maxPixel) }).value else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key, cost: cg.width * cg.height * 4)
        return image
    }

    /// Drops every cached size of `url` (after the file was edited).
    static func invalidate(_ url: URL) {
        for size in usedSizes { cache.removeObject(forKey: key(url, size)) }
    }

    /// Full-resolution pixel dimensions, read from the header (no decode).
    static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    private static func decode(_ url: URL, _ maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
