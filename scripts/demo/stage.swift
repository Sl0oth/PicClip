// Backdrop for recording README media: hides the real desktop and shows fake content to screenshot.
// Usage: stage <scene-file>   (write "poster", "chat", "payment" or "none" into the file to switch scenes)
import AppKit
import SwiftUI

@Observable final class Scene { var name = "poster" }
let scene = Scene()

struct Backdrop: View {
    let scene: Scene
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.16, green: 0.19, blue: 0.29), Color(red: 0.31, green: 0.24, blue: 0.38)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            switch scene.name {
            case "poster": Poster().offset(x: 760, y: 420)
            case "payment": Payment().offset(x: 740, y: 400)
            case "chat": Chat().offset(x: 700, y: 360)
            default: EmptyView()
            }
        }
        .ignoresSafeArea()
    }
}

struct Poster: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(red: 1, green: 0.55, blue: 0.35), Color(red: 0.93, green: 0.33, blue: 0.53)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(red: 1, green: 0.85, blue: 0.4)).frame(width: 120).offset(x: 380, y: -190)
            VStack(alignment: .leading, spacing: 6) {
                Text("Lisbon").font(.system(size: 54, weight: .bold))
                Text("Sat 12 Apr · 24° and sunny").font(.system(size: 20, weight: .medium)).opacity(0.9)
                Text("Flight TP 1337 · Gate 14 · 09:40").font(.system(size: 16, weight: .regular)).opacity(0.75)
            }
            .foregroundStyle(.white)
            .padding(32)
        }
        .frame(width: 540, height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }
}

/// A plain chat card that accepts real image drops (for the "drag into any app" clip).
struct Chat: View {
    @State private var dropped: [NSImage] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sam").font(.system(size: 22, weight: .bold))
            Divider()
            Text("Can you send me what you're seeing?")
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            ForEach(dropped.indices, id: \.self) { i in
                Image(nsImage: dropped[i]).resizable().scaledToFit().frame(maxWidth: 260, maxHeight: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 14)).frame(maxWidth: .infinity, alignment: .trailing)
            }
            Spacer(minLength: 0)
            Text("Message").foregroundStyle(.black.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black.opacity(0.15)))
        }
        .font(.system(size: 17))
        .foregroundStyle(.black.opacity(0.85))
        .padding(24)
        .frame(width: 460, height: 440)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        .dropDestination(for: URL.self) { urls, _ in
            dropped += urls.compactMap { NSImage(contentsOf: $0) }
            return !urls.isEmpty
        }
    }
}

struct Payment: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Checkout").font(.system(size: 30, weight: .bold))
            row("Name", "Alex Rivera")
            row("Email", "alex.rivera@example.com")
            row("Card", "4242 4242 4242 4242")
            row("Address", "742 Evergreen Terrace")
            Divider()
            HStack { Text("Total").font(.system(size: 18, weight: .semibold)); Spacer(); Text("$84.20").font(.system(size: 18, weight: .bold)) }
        }
        .foregroundStyle(.black.opacity(0.85))
        .padding(30)
        .frame(width: 560)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }
    func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.black.opacity(0.45)).frame(width: 90, alignment: .leading); Text(v).fontWeight(.medium) }
            .font(.system(size: 19))
    }
}

let sceneFile = URL(fileURLWithPath: CommandLine.arguments[1])
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let screen = NSScreen.main!
    let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1) // covers every app window; PicClip floats above
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]
    window.contentView = NSHostingView(rootView: Backdrop(scene: scene))
    window.orderFrontRegardless()
    Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
        let name = ((try? String(contentsOf: sceneFile, encoding: .utf8)) ?? "poster").trimmingCharacters(in: .whitespacesAndNewlines)
        if name != scene.name { scene.name = name }
    }
    app.run()
}
