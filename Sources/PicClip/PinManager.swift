import AppKit

/// Always-on-top, resizable copies of a screenshot. Drag to move, double-click to open in the library.
@MainActor
final class PinManager {
    var onOpen: (Screenshot) -> Void = { _ in }
    private var pins: [FloatingPanel] = []

    /// `origin` is the frame to grow from (e.g. the preview being pinned).
    func pin(_ shot: Screenshot, from origin: NSRect? = nil) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        Task {
            guard let screen, let image = await Thumbnails.image(for: shot.url, maxPixel: 2400) else { return }
            present(shot, image: image, on: screen, from: origin)
        }
    }

    private func present(_ shot: Screenshot, image: NSImage, on screen: NSScreen, from origin: NSRect?) {
        let visible = screen.visibleFrame
        // Image pixels → points at the screen's scale, capped to 60% of the screen.
        var size = NSSize(width: image.size.width / screen.backingScaleFactor,
                          height: image.size.height / screen.backingScaleFactor)
        let fit = min(1, visible.width * 0.6 / size.width, visible.height * 0.6 / size.height)
        size = NSSize(width: (size.width * fit).rounded(), height: (size.height * fit).rounded())
        let cascade = CGFloat(pins.count % 8) * 24
        let target = NSRect(x: visible.midX - size.width / 2 + cascade, y: visible.midY - size.height / 2 - cascade,
                            width: size.width, height: size.height)

        let panel = FloatingPanel(frame: origin ?? target, level: .floating, resizable: true)
        panel.contentAspectRatio = size
        panel.minSize = NSSize(width: 60, height: 60 * size.height / max(size.width, 1))
        panel.setCard(FloatingCard(
            model: CardModel(shot: shot, image: image), mode: .moveWindow, cornerRadius: 8,
            onClose: { [weak self, weak panel] in self?.unpin(panel) },
            onClick: { [weak self] in self?.onOpen(shot) }
        ))
        pins.append(panel)
        panel.show()
        if origin != nil {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                panel.animator().setFrame(target, display: true)
            }
        }
    }

    private func unpin(_ panel: FloatingPanel?) {
        guard let panel else { return }
        pins.removeAll { $0 === panel }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 },
                                             completionHandler: { panel.orderOut(nil) })
    }
}
