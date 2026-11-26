// Writes fake screenshots (tagged like real ones) so the library has tidy demo content.
// Usage: fakeshots <folder>
import AppKit
import SwiftUI

let folder = URL(fileURLWithPath: CommandLine.arguments[1])

struct Card<Content: View>: View {
    let colors: [Color]
    @ViewBuilder let content: Content
    var body: some View {
        ZStack { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing); content }
            .frame(width: 600, height: 400)
            .foregroundStyle(.white)
    }
}

@MainActor func shots() -> [(String, AnyView)] { [
    ("Chart", AnyView(Card(colors: [.indigo, .purple]) {
        VStack(alignment: .leading) {
            Text("Weekly active users").font(.system(size: 26, weight: .bold))
            HStack(alignment: .bottom, spacing: 18) {
                ForEach([0.35, 0.5, 0.42, 0.66, 0.58, 0.8, 0.92], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.85)).frame(width: 46, height: 230 * h)
                }
            }.frame(height: 240, alignment: .bottom)
        }.padding(40)
    })),
    ("Code", AnyView(Card(colors: [Color(white: 0.12), Color(white: 0.2)]) {
        Text("func greet(_ name: String) -> String {\n    \"Hello, \\(name)!\"\n}\n\nprint(greet(\"PicClip\"))")
            .font(.system(size: 24, design: .monospaced)).foregroundStyle(.green).padding(40)
            .frame(maxWidth: .infinity, alignment: .leading)
    })),
    ("Palette", AnyView(Card(colors: [.white, .white]) {
        HStack(spacing: 0) { ForEach([Color.orange, .pink, .purple, .blue, .teal], id: \.self) { $0 } }
    })),
    ("Order", AnyView(Card(colors: [.teal, .green]) {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox.fill").font(.system(size: 70))
            Text("Order #2481 shipped").font(.system(size: 30, weight: .bold))
            Text("Arrives Thursday").font(.system(size: 20)).opacity(0.85)
        }
    })),
    ("Map", AnyView(Card(colors: [.blue, .cyan]) {
        VStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse").font(.system(size: 80))
            Text("Coffee in 4 min").font(.system(size: 30, weight: .bold))
        }
    })),
] }

MainActor.assumeIsolated {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let tag = Data([0x62,0x70,0x6C,0x69,0x73,0x74,0x30,0x30,0x09,0x08,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9])
    for (i, (name, view)) in shots().enumerated() {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { continue }
        let url = folder.appending(path: "Screenshot demo \(i + 1) \(name).png")
        let rep = NSBitmapImageRep(cgImage: cg)
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
        _ = tag.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, tag.count, 0, 0) }
        let date = Date().addingTimeInterval(-Double(i + 1) * 1800) // spread over the last few hours
        try? FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
        print("wrote", url.lastPathComponent)
    }
}
