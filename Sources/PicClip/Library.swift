import AppKit
import SwiftUI

@MainActor @Observable
final class LibraryModel {
    var selection: URL?
    var scrollRequest: URL? // set when something outside the window picks a screenshot
    var tool: EditTool = .select
    var markerColor: MarkerColor = .red
    var markerSize: MarkerSize = .medium
    private(set) var editor: Editor?
    @ObservationIgnored private let store: ScreenshotStore

    init(store: ScreenshotStore) { self.store = store }

    /// Keeps one editor for the selected screenshot. Leaving a screenshot saves its edits (like Markup's "Done").
    func syncEditor(to shot: Screenshot?) {
        guard editor?.url != shot?.url else { return }
        if let old = editor, old.isDirty { Task { await old.save() } }
        editor = shot.map { Editor(url: $0.url, onSaved: { [store] in store.didEdit($0) }) }
    }

    /// Saves pending edits on `url` before something else reads the file (copy, pin, share…).
    func commit(_ url: URL) async {
        if let editor, editor.url == url { await editor.save() }
    }
}

@MainActor
final class LibraryController: NSObject, NSWindowDelegate {
    var onPin: (Screenshot) -> Void = { _ in }
    private let store: ScreenshotStore
    private let model: LibraryModel
    private var window: NSWindow?

    init(store: ScreenshotStore) {
        self.store = store
        self.model = LibraryModel(store: store)
    }

    func show(selecting shot: Screenshot? = nil) {
        if let shot {
            model.selection = shot.url
            model.scrollRequest = shot.url
        }
        let window = window ?? makeWindow()
        NSApp.setActivationPolicy(.regular) // Dock icon + menu bar while the library is open
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: LibraryView(store: store, model: model, onPin: { [weak self] in self?.onPin($0) }))
        host.sceneBridgingOptions = [.toolbars] // title bridging shows "Untitled" in AppKit-hosted windows
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.title = "Screenshots"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.center()
        window.setFrameAutosaveName("PicClipLibrary")
        // Demo mode (README recording): sit above the recording backdrop, below pins and previews.
        if UserDefaults.standard.bool(forKey: "DemoMode") { window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 2) }
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        if let url = model.editor?.url { Task { await model.commit(url) } }
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Library

struct LibraryView: View {
    let store: ScreenshotStore
    @Bindable var model: LibraryModel
    let onPin: (Screenshot) -> Void

    private var selected: Screenshot? {
        model.selection.flatMap { url in store.shots.first { $0.url == url } }
    }

    var body: some View {
        Group {
            if store.shots.isEmpty {
                ContentUnavailableView("No Screenshots Yet", systemImage: "camera.viewfinder",
                                       description: Text("Press ⇧⌘4 to capture part of your screen.\nIt'll show up here and in the corner of your screen."))
            } else {
                HSplitView {
                    grid.frame(minWidth: 240, idealWidth: 340, maxWidth: 560)
                    detail.frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .toolbar { toolbar }
        .onChange(of: selected, initial: true) { _, shot in model.syncEditor(to: shot) }
    }

    // MARK: Grid

    private var days: [(day: Date, shots: [Screenshot])] {
        let calendar = Calendar.current
        return Dictionary(grouping: store.shots) { calendar.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value) }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 8)],
                          spacing: 10, pinnedViews: [.sectionHeaders]) {
                    ForEach(days, id: \.day) { group in
                        Section {
                            ForEach(group.shots) { shot in
                                ThumbnailCell(shot: shot, isSelected: model.selection == shot.url,
                                              revision: store.revisions[shot.url, default: 0])
                                    .id(shot.url)
                                    .onTapGesture(count: 2) { ImageActions.openInPreview(shot.url) }
                                    .simultaneousGesture(TapGesture().onEnded { model.selection = shot.url })
                                    .onDrag { NSItemProvider(contentsOf: shot.url) ?? NSItemProvider() }
                                    .contextMenu { menuItems(for: shot) }
                            }
                        } header: {
                            DayHeader(day: group.day, count: group.shots.count)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .onChange(of: model.scrollRequest, initial: true) { _, url in
                guard let url else { return }
                proxy.scrollTo(url, anchor: .center)
                model.scrollRequest = nil
            }
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let selected, let editor = model.editor, editor.url == selected.url {
            EditorPane(shot: selected, editor: editor, model: model)
                .id(selected.url)
                .contextMenu { if model.tool == .select { menuItems(for: selected) } }
        } else {
            ContentUnavailableView("Pick a Screenshot", systemImage: "photo.on.rectangle.angled",
                                   description: Text("Select one on the left to view, mark up, or blur it."))
        }
    }

    // MARK: Actions

    @ViewBuilder private func menuItems(for shot: Screenshot) -> some View {
        Button("Copy") { act(shot) { ImageActions.copy($0.url) } }
        Button("Pin to Screen") { act(shot, onPin) }
        Button("Open in Preview") { act(shot) { ImageActions.openInPreview($0.url) } }
        Button("Show in Finder") { ImageActions.reveal(shot.url) }
        Divider()
        Button("Move to Trash") { trash(shot) }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Group {
                Button("Copy", systemImage: "doc.on.doc") { selected.map { act($0) { ImageActions.copy($0.url) } } }
                    .keyboardShortcut("c")
                    .help("Copy (⌘C)")
                Button("Pin to Screen", systemImage: "pin") { selected.map { act($0, onPin) } }
                    .help("Pin to Screen — floats above every window")
                Button("Show in Finder", systemImage: "folder") { selected.map { ImageActions.reveal($0.url) } }
                    .help("Show in Finder")
                if let selected {
                    ShareLink(item: selected.url).help("Share")
                }
                Button("Move to Trash", systemImage: "trash") { selected.map(trash) }
                    .keyboardShortcut(.delete)
                    .help("Move to Trash (⌘⌫)")
            }
            .disabled(selected == nil)
        }
    }

    /// Runs `action` after pending edits are saved, so it sees the edited file.
    private func act(_ shot: Screenshot, _ action: @escaping (Screenshot) -> Void) {
        Task {
            await model.commit(shot.url)
            action(shot)
        }
    }

    private func trash(_ shot: Screenshot) {
        if model.selection == shot.url, let i = store.shots.firstIndex(of: shot) {
            model.editor?.revert() // don't bother saving something being thrown away
            let neighbor = store.shots.indices.contains(i + 1) ? store.shots[i + 1] : (i > 0 ? store.shots[i - 1] : nil)
            model.selection = neighbor?.url
        }
        ImageActions.trash(shot.url)
    }
}

private struct DayHeader: View {
    let day: Date
    let count: Int

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        return day.formatted(sameYear ? .dateTime.weekday(.wide).month(.wide).day() : .dateTime.month(.wide).day().year())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            Text("\(count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct ThumbnailCell: View {
    let shot: Screenshot
    let isSelected: Bool
    let revision: Int
    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.quaternary)
                }
            }
            .frame(height: 92)
            .frame(maxWidth: .infinity)
            .padding(7)
            .background(background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))

            Text(shot.date, format: .dateTime.hour().minute())
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear), in: Capsule())
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .task(id: revision) { image = await Thumbnails.image(for: shot.url, maxPixel: 360) }
    }

    private var background: AnyShapeStyle {
        isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : hovering ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear)
    }
}

// MARK: - Editor pane

private struct EditorPane: View {
    let shot: Screenshot
    let editor: Editor
    @Bindable var model: LibraryModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                canvas
                    .padding(EdgeInsets(top: 24, leading: 28, bottom: 118, trailing: 28))
            }
            // An overlay never changes the pane's size, so a wide palette can't stretch or zoom the image.
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    Text(editor.isSaving ? "Saving…" : model.tool.hint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                    EditPalette(editor: editor, model: model)
                        .fixedSize()
                }
                .padding(.bottom, 16)
            }
            .clipped()
            Divider()
            InfoBar(shot: shot, editor: editor)
        }
        .task { await editor.load() }
        .onChange(of: model.tool, initial: true) { _, tool in
            if tool == .blur || tool == .pixelate { editor.prepareFilters() }
        }
    }

    @ViewBuilder private var canvas: some View {
        if let image = editor.display {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .overlay {
                    GeometryReader { geo in
                        Canvas { context, size in
                            context.withCGContext { editor.render(in: $0, canvas: size) }
                        }
                        .contentShape(Rectangle())
                        .gesture(drawGesture(canvas: geo.size), including: model.tool == .select ? .subviews : .all)
                        .pointerStyle(model.tool == .select ? nil : .rectSelection)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                .modifier(FileDrag(url: shot.url, enabled: model.tool == .select))
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func drawGesture(canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                editor.drag(tool: model.tool, from: value.startLocation, to: value.location, canvas: canvas,
                            color: model.markerColor, size: model.markerSize)
            }
            .onEnded { _ in editor.endDrag() }
    }
}

private struct EditPalette: View {
    let editor: Editor
    @Bindable var model: LibraryModel

    var body: some View {
        VStack(spacing: 6) {
            // Marker options get their own small bar, so the main palette stays narrow in any window size.
            if model.tool == .marker {
                HStack(spacing: 2) {
                    ForEach(MarkerColor.allCases) { color in
                        Button { model.markerColor = color } label: {
                            Circle().fill(color.color)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                                .padding(3)
                                .overlay(Circle().strokeBorder(model.markerColor == color ? Color.primary.opacity(0.7) : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                    separator
                    ForEach(MarkerSize.allCases) { size in
                        Button { model.markerSize = size } label: {
                            Circle().fill(.primary)
                                .frame(width: 3 + size.rawValue * 0.8, height: 3 + size.rawValue * 0.8)
                                .frame(width: 24, height: 24)
                                .background(model.markerSize == size ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .modifier(PaletteBackground())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 2) {
                ForEach(EditTool.allCases) { tool in
                    PaletteButton(symbol: tool.symbol, help: "\(tool.title) (\(tool.key.character.uppercased()))",
                                  isOn: model.tool == tool) { model.tool = tool }
                        .keyboardShortcut(tool.key, modifiers: [])
                }
                separator
                PaletteButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)", isOn: false, action: editor.undo)
                    .keyboardShortcut("z")
                    .disabled(!editor.isDirty)
                PaletteButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)", isOn: false, action: editor.redo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!editor.canRedo)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .modifier(PaletteBackground())
        }
        .animation(.snappy(duration: 0.2), value: model.tool)
    }

    private var separator: some View {
        Divider().frame(height: 18).padding(.horizontal, 5)
    }
}

private struct PaletteButton: View {
    let symbol: String
    let help: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 28)
                .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(isOn ? AnyShapeStyle(Color.accentColor) : hovering && isEnabled ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Drag the file out — only when no drawing tool is active, so drawing never starts a file drag.
private struct FileDrag: ViewModifier {
    let url: URL
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() } } else { content }
    }
}

/// Liquid Glass where available, regular material otherwise.
private struct PaletteBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        }
    }
}

private struct InfoBar: View {
    let shot: Screenshot
    let editor: Editor

    private var fileSize: String? {
        (try? shot.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Label(shot.date.formatted(.dateTime.weekday().month().day().hour().minute()), systemImage: "calendar")
            if editor.pixelSize != .zero {
                Label("\(Int(editor.pixelSize.width)) × \(Int(editor.pixelSize.height))", systemImage: "aspectratio")
            }
            if !editor.isDirty, let fileSize { Label(fileSize, systemImage: "doc") }
            Spacer(minLength: 8)
            if editor.isDirty {
                Label("Edited", systemImage: "pencil.circle.fill")
                    .foregroundStyle(.orange)
                Button("Revert", action: editor.revert)
                    .controlSize(.small)
                Button("Save") { Task { await editor.save() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut("s")
                    .disabled(editor.isSaving)
            }
        }
        .lineLimit(1)
        .font(.callout)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .animation(.snappy(duration: 0.2), value: editor.isDirty)
    }
}
