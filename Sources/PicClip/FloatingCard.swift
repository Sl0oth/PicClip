import AppKit
import SwiftUI

// Shared building blocks for the floating preview and pinned windows.

@MainActor @Observable
final class CardModel {
    let shot: Screenshot
    var image: NSImage
    var hovering = false
    var copied = false

    init(shot: Screenshot, image: NSImage) {
        self.shot = shot
        self.image = image
    }

    func copy() {
        ImageActions.copy(shot.url)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

enum DragPhase { case began, ended(dropped: Bool) }

struct FloatingCard: View {
    let model: CardModel
    let mode: MouseSurfaceView.Mode
    let cornerRadius: CGFloat
    let onClose: () -> Void
    let onClick: () -> Void
    var onPin: (() -> Void)? = nil
    var onDrag: (DragPhase) -> Void = { _ in }

    var body: some View {
        ZStack {
            Image(nsImage: model.image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            MouseSurface(mode: mode, url: model.shot.url, image: model.image,
                         onHover: { model.hovering = $0 }, onClick: onClick, onDrag: onDrag)
            if model.hovering { chrome.transition(.opacity) }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        .animation(.easeOut(duration: 0.12), value: model.hovering)
    }

    private var chrome: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.28), .clear, .black.opacity(0.28)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack {
                HStack {
                    HUDButton(symbol: "xmark", help: "Dismiss", action: onClose)
                    Spacer()
                }
                Spacer()
                HStack(spacing: 6) {
                    Spacer()
                    HUDButton(symbol: model.copied ? "checkmark" : "doc.on.doc", help: "Copy", action: model.copy)
                    if let onPin { HUDButton(symbol: "pin", help: "Pin to Screen", action: onPin) }
                }
            }
            .padding(6)
        }
    }
}

struct HUDButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24, height: 24)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - AppKit mouse handling (hover, click, file drag-out, window move)

struct MouseSurface: NSViewRepresentable {
    let mode: MouseSurfaceView.Mode
    let url: URL
    let image: NSImage
    let onHover: (Bool) -> Void
    let onClick: () -> Void
    let onDrag: (DragPhase) -> Void

    func makeNSView(context: Context) -> MouseSurfaceView { MouseSurfaceView() }

    func updateNSView(_ view: MouseSurfaceView, context: Context) {
        view.mode = mode
        view.url = url
        view.image = image
        view.onHover = onHover
        view.onClick = onClick
        view.onDrag = onDrag
    }
}

final class MouseSurfaceView: NSView, NSDraggingSource {
    enum Mode { case dragOut, moveWindow }

    var mode = Mode.dragOut
    var url: URL?
    var image: NSImage?
    var onHover: (Bool) -> Void = { _ in }
    var onClick: () -> Void = {}
    var onDrag: (DragPhase) -> Void = { _ in }
    private var mouseDownEvent: NSEvent?

    override init(frame: NSRect) {
        super.init(frame: frame)
        // .activeAlways: hover works even though our panels never become key.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    override func mouseDown(with event: NSEvent) {
        switch mode {
        case .dragOut: mouseDownEvent = event
        case .moveWindow:
            if event.clickCount == 2 { onClick() } else { window?.performDrag(with: event) }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .dragOut, let down = mouseDownEvent, let url else { return }
        let a = down.locationInWindow, b = event.locationInWindow
        guard hypot(b.x - a.x, b.y - a.y) > 4 else { return }
        mouseDownEvent = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        onDrag(.began)
        beginDraggingSession(with: [item], event: down, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if mode == .dragOut, mouseDownEvent != nil { onClick() }
        mouseDownEvent = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDrag(.ended(dropped: operation != []))
    }
}

// MARK: - Window

private final class CardHostingView: NSHostingView<FloatingCard> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Borderless, transparent, non-activating panel — floats without stealing focus from the app you're in.
final class FloatingPanel: NSPanel {
    convenience init(frame: NSRect, level: NSWindow.Level, resizable: Bool) {
        var style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        if resizable { style.insert(.resizable) }
        self.init(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        isFloatingPanel = true
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setCard(_ card: FloatingCard) {
        let host = CardHostingView(rootView: card)
        host.sizingOptions = [] // the window decides the size, not SwiftUI
        contentView = host
    }

    func show() {
        orderFrontRegardless()
        DispatchQueue.main.async { self.invalidateShadow() } // shadow follows the rounded corners
    }
}
