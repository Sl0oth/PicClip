import AppKit

/// The persistent bottom-right thumbnails. Newest sits at the bottom; older ones stack upward.
@MainActor
final class PreviewManager {
    var onOpen: (Screenshot) -> Void = { _ in }
    var onPin: (Screenshot, NSRect) -> Void = { _, _ in }

    private final class Preview {
        let panel: FloatingPanel
        let model: CardModel
        let screen: NSScreen
        init(panel: FloatingPanel, model: CardModel, screen: NSScreen) {
            self.panel = panel
            self.model = model
            self.screen = screen
        }
    }

    private var previews: [Preview] = [] // oldest first
    private let maxCount = 4
    private let margin: CGFloat = 16
    private let spacing: CGFloat = 10
    private let level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1) // above pins

    func show(_ shot: Screenshot) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        Task {
            guard let screen, let image = await Thumbnails.image(for: shot.url, maxPixel: 600),
                  !previews.contains(where: { $0.model.shot == shot }) else { return }
            present(shot, image: image, on: screen)
        }
    }

    private func present(_ shot: Screenshot, image: NSImage, on screen: NSScreen) {
        let panel = FloatingPanel(frame: NSRect(origin: .zero, size: cardSize(for: image.size)), level: level, resizable: false)
        let model = CardModel(shot: shot, image: image)
        let preview = Preview(panel: panel, model: model, screen: screen)

        panel.setCard(FloatingCard(
            model: model, mode: .dragOut, cornerRadius: 10,
            onClose: { [weak self, weak preview] in self?.dismiss(preview) },
            onClick: { [weak self, weak preview] in
                self?.dismiss(preview)
                self?.onOpen(shot)
            },
            onPin: { [weak self, weak preview] in
                guard let self, let preview else { return }
                onPin(shot, preview.panel.frame)
                dismiss(preview, animated: false)
            },
            onDrag: { [weak self, weak preview] phase in
                guard let self, let preview else { return }
                switch phase {
                case .began: preview.panel.alphaValue = 0 // the drag image *is* the thumbnail
                case .ended(dropped: true): dismiss(preview, animated: false)
                case .ended(dropped: false): preview.panel.animator().alphaValue = 1
                }
            }
        ))

        previews.append(preview)
        if previews.count > maxCount { dismiss(previews.first) }
        layout(newcomer: preview)
    }

    private func dismiss(_ preview: Preview?, animated: Bool = true) {
        guard let preview, let index = previews.firstIndex(where: { $0 === preview }) else { return }
        previews.remove(at: index)
        let panel = preview.panel
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().setFrame(panel.frame.offsetBy(dx: panel.frame.width + margin, dy: 0), display: true)
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        } else {
            panel.orderOut(nil)
        }
        layout()
    }

    private func layout(newcomer: Preview? = nil) {
        var nextY: [ObjectIdentifier: CGFloat] = [:]
        var targets: [(Preview, NSRect)] = []
        for preview in previews.reversed() {
            let visible = preview.screen.visibleFrame
            let key = ObjectIdentifier(preview.screen)
            let y = nextY[key] ?? visible.minY + margin
            let size = preview.panel.frame.size
            targets.append((preview, NSRect(x: visible.maxX - margin - size.width, y: y, width: size.width, height: size.height)))
            nextY[key] = y + size.height + spacing
        }

        if let newcomer, let target = targets.first(where: { $0.0 === newcomer })?.1 {
            newcomer.panel.setFrame(target.offsetBy(dx: target.width + margin, dy: 0), display: false)
            newcomer.panel.alphaValue = 0
            newcomer.panel.show()
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1) // quick ease-out, slight settle
            for (preview, frame) in targets {
                preview.panel.animator().setFrame(frame, display: true)
                if preview === newcomer { preview.panel.animator().alphaValue = 1 }
            }
        }
    }

    private func cardSize(for size: NSSize) -> NSSize {
        guard size.width > 0, size.height > 0 else { return NSSize(width: 200, height: 130) }
        let scale = min(220 / size.width, 150 / size.height)
        return NSSize(width: max(90, (size.width * scale).rounded()), height: max(60, (size.height * scale).rounded()))
    }
}
