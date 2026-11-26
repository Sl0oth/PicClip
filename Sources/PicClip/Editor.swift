import AppKit
import CoreImage
import ImageIO
import SwiftUI

// MARK: - Tools & settings

enum EditTool: String, CaseIterable, Identifiable {
    case select, marker, redact, blur, pixelate
    var id: Self { self }

    var title: String {
        switch self {
        case .select: "Select"
        case .marker: "Marker"
        case .redact: "Black Out"
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .marker: "scribble.variable"
        case .redact: "rectangle.fill"
        case .blur: "drop.halffull"
        case .pixelate: "checkerboard.rectangle"
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .select: "v"
        case .marker: "m"
        case .redact: "r"
        case .blur: "b"
        case .pixelate: "p"
        }
    }

    var hint: String {
        switch self {
        case .select: "Drag the image into any app"
        case .marker: "Draw on the screenshot"
        case .redact: "Drag over anything you want hidden for good"
        case .blur: "Drag over an area to blur it"
        case .pixelate: "Drag over an area to pixelate it"
        }
    }

    var kind: Annotation.Kind? {
        switch self {
        case .select: nil
        case .marker: .marker
        case .redact: .redact
        case .blur: .blur
        case .pixelate: .pixelate
        }
    }
}

enum MarkerColor: CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, black
    var id: Self { self }
    var color: Color { Color(nsColor: nsColor) }
    var nsColor: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .black: .black
        }
    }
}

enum MarkerSize: CGFloat, CaseIterable, Identifiable {
    case small = 3, medium = 6, large = 12 // points on screen while drawing
    var id: Self { self }
}

// MARK: - Annotations & rendering

struct Annotation {
    enum Kind { case marker, redact, blur, pixelate }
    var kind: Kind
    var points: [CGPoint] // image pixels, y-down. Marker: the path. Others: [start, current corner].
    var color: CGColor = .black
    var width: CGFloat = 0 // image pixels

    var rect: CGRect {
        guard let a = points.first, let b = points.last else { return .null }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

/// One renderer for the live canvas and the full-res export, so what you see is exactly what gets saved.
enum AnnotationRenderer {
    private static let ciContext = CIContext()

    /// Draws into a **y-down** context covering `canvas`. Annotation coordinates are in image pixels (`pixelSize`).
    static func draw(_ items: [Annotation], in cg: CGContext, canvas: CGSize, pixelSize: CGSize,
                     blurred: CGImage?, pixelated: CGImage?) {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return }
        let sx = canvas.width / pixelSize.width, sy = canvas.height / pixelSize.height
        let map = { (p: CGPoint) in CGPoint(x: p.x * sx, y: p.y * sy) }

        for item in items {
            switch item.kind {
            case .marker:
                guard let first = item.points.first else { continue }
                let p = item.points.map(map)
                cg.saveGState()
                cg.setStrokeColor(item.color)
                cg.setLineWidth(item.width * sx)
                cg.setLineCap(.round)
                cg.setLineJoin(.round)
                cg.beginPath()
                cg.move(to: map(first))
                if p.count < 3 {
                    cg.addLine(to: p.last!) // a single tap still leaves a dot (round cap)
                } else {
                    for i in 1..<(p.count - 1) { // smooth through midpoints
                        cg.addQuadCurve(to: CGPoint(x: (p[i].x + p[i + 1].x) / 2, y: (p[i].y + p[i + 1].y) / 2), control: p[i])
                    }
                    cg.addLine(to: p.last!)
                }
                cg.strokePath()
                cg.restoreGState()

            case .redact:
                let r = item.rect
                cg.setFillColor(.black)
                cg.fill(CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy))

            case .blur, .pixelate:
                let r = item.rect
                let target = CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy)
                cg.saveGState()
                cg.clip(to: target)
                if let filtered = item.kind == .blur ? blurred : pixelated {
                    drawImage(filtered, in: cg, rect: CGRect(origin: .zero, size: canvas))
                } else { // filter still computing — show where it will go
                    cg.setFillColor(gray: 0.5, alpha: 0.6)
                    cg.fill(target)
                }
                cg.restoreGState()
            }
        }
    }

    /// CGContext.draw assumes y-up; flip locally so images land upright in our y-down space.
    private static func drawImage(_ image: CGImage, in cg: CGContext, rect: CGRect) {
        cg.saveGState()
        cg.translateBy(x: rect.minX, y: rect.maxY)
        cg.scaleBy(x: 1, y: -1)
        cg.draw(image, in: CGRect(origin: .zero, size: rect.size))
        cg.restoreGState()
    }

    /// Blurred and pixelated copies of the whole image. Strength is relative to image size,
    /// so the 3000px live preview and the full-res export look the same.
    static func filtered(_ image: CGImage) -> (blurred: CGImage?, pixelated: CGImage?) {
        let input = CIImage(cgImage: image)
        let extent = input.extent
        let longest = max(extent.width, extent.height)
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: max(10, longest / 55)).cropped(to: extent)
        let pixelated = input.clampedToExtent().applyingFilter("CIPixellate", parameters: [
            kCIInputScaleKey: max(10, longest / 70),
            kCIInputCenterKey: CIVector(x: 0, y: 0),
        ]).cropped(to: extent)
        return (ciContext.createCGImage(blurred, from: extent), ciContext.createCGImage(pixelated, from: extent))
    }

    /// Burns the annotations into the file at full resolution, in place (keeps Finder/Spotlight screenshot metadata).
    static func export(_ items: [Annotation], to url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        let size = CGSize(width: image.width, height: image.height)
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cg = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        drawImage(image, in: cg, rect: CGRect(origin: .zero, size: size))
        let needsFilters = items.contains { $0.kind == .blur || $0.kind == .pixelate }
        let filters: (blurred: CGImage?, pixelated: CGImage?) = needsFilters ? filtered(image) : (nil, nil)
        draw(items, in: cg, canvas: size, pixelSize: size, blurred: filters.blurred, pixelated: filters.pixelated)

        guard let output = cg.makeImage() else { return false }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, output, CGImageSourceCopyPropertiesAtIndex(source, 0, nil)) // keeps DPI
        guard CGImageDestinationFinalize(destination) else { return false }
        do {
            let handle = try FileHandle(forWritingTo: url) // in place, not atomic-replace: xattrs survive
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data as Data)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Editor state (one per open screenshot)

@MainActor @Observable
final class Editor {
    let url: URL
    private(set) var display: NSImage?
    private(set) var pixelSize: CGSize = .zero
    private(set) var annotations: [Annotation] = []
    private(set) var current: Annotation?
    private(set) var isSaving = false
    @ObservationIgnored private var redoStack: [Annotation] = []
    private(set) var canRedo = false
    @ObservationIgnored private let onSaved: (URL) -> Void
    private var blurred: CGImage?
    private var pixelated: CGImage?
    @ObservationIgnored private var filtering = false

    var isDirty: Bool { !annotations.isEmpty }
    var visibleAnnotations: [Annotation] { current.map { annotations + [$0] } ?? annotations }

    init(url: URL, onSaved: @escaping (URL) -> Void) {
        self.url = url
        self.onSaved = onSaved
    }

    func load() async {
        // Cached grid thumbnail first (instant), then the sharp one.
        if display == nil { display = await Thumbnails.image(for: url, maxPixel: 360) }
        display = await Thumbnails.image(for: url, maxPixel: 3000) ?? display
        pixelSize = Thumbnails.pixelSize(of: url) ?? display?.size ?? .zero
        blurred = nil
        pixelated = nil
    }

    func render(in cg: CGContext, canvas: CGSize) {
        AnnotationRenderer.draw(visibleAnnotations, in: cg, canvas: canvas, pixelSize: pixelSize,
                                blurred: blurred, pixelated: pixelated)
    }

    func prepareFilters() {
        guard blurred == nil, !filtering, let cg = display?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        filtering = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { AnnotationRenderer.filtered(cg) }.value
            blurred = result.blurred
            pixelated = result.pixelated
            filtering = false
        }
    }

    // MARK: Drawing

    func drag(tool: EditTool, from start: CGPoint, to point: CGPoint, canvas: CGSize, color: MarkerColor, size: MarkerSize) {
        guard let kind = tool.kind, canvas.width > 0, pixelSize.width > 0 else { return }
        let scale = pixelSize.width / canvas.width
        let p = clamp(CGPoint(x: point.x * scale, y: point.y * scale))
        // Mutate a local copy and assign once: no overlapping access, one redraw per move.
        var item = current ?? {
            if kind == .blur || kind == .pixelate { prepareFilters() }
            return Annotation(kind: kind, points: [clamp(CGPoint(x: start.x * scale, y: start.y * scale))],
                              color: color.nsColor.cgColor, width: size.rawValue * scale)
        }()
        if kind == .marker {
            // Skip points closer than ~1.5pt on screen — smoother line, far less work.
            if let last = item.points.last, current != nil, hypot(p.x - last.x, p.y - last.y) < 1.5 * scale { return }
            item.points.append(p)
        } else {
            item.points = [item.points[0], p]
        }
        current = item
    }

    func endDrag() {
        guard let item = current else { return }
        current = nil
        let r = item.rect
        guard item.kind == .marker || (r.width > 2 && r.height > 2) else { return }
        annotations.append(item)
        redoStack.removeAll()
        canRedo = false
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), pixelSize.width), y: min(max(p.y, 0), pixelSize.height))
    }

    // MARK: History

    func undo() {
        guard let item = annotations.popLast() else { return }
        redoStack.append(item)
        canRedo = true
    }

    func redo() {
        guard let item = redoStack.popLast() else { return }
        annotations.append(item)
        canRedo = !redoStack.isEmpty
    }

    func revert() {
        annotations.removeAll()
        redoStack.removeAll()
        canRedo = false
    }

    @discardableResult
    func save() async -> Bool {
        guard isDirty, !isSaving else { return true }
        isSaving = true
        let items = annotations, url = url
        let ok = await Task.detached(priority: .userInitiated) { AnnotationRenderer.export(items, to: url) }.value
        if ok {
            Thumbnails.invalidate(url)
            await load()
            revert() // edits are now part of the file
            onSaved(url)
        } else {
            NSSound.beep()
        }
        isSaving = false
        return ok
    }
}
