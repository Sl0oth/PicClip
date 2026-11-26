// Turns a screen recording (.mov from ⇧⌘5) into a README-ready GIF. No dependencies.
// Usage: swift scripts/make-gif.swift <in.mov> <out.gif> [width=880] [fps=15] [start=0] [end=full]
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: swift scripts/make-gif.swift <in.mov> <out.gif> [width=880] [fps=15] [startSeconds=0] [endSeconds=full]")
    exit(1)
}
let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
let width = args.count > 3 ? Double(args[3])! : 880
let fps = args.count > 4 ? Double(args[4])! : 15
let start = args.count > 5 ? Double(args[5])! : 0

let asset = AVURLAsset(url: input)
let done = DispatchSemaphore(value: 0)
Task {
    do {
        let duration = try await asset.load(.duration).seconds
        let end = args.count > 6 ? min(Double(args[6])!, duration) : duration
        let times = stride(from: start, to: end, by: 1 / fps).map { CMTime(seconds: $0, preferredTimescale: 600) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: width, height: 0) // keep aspect
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        guard let gif = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, times.count, nil) else {
            print("can't write \(output.path)"); exit(1)
        }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary

        var count = 0
        for await result in generator.images(for: times) {
            if let image = try? result.image {
                CGImageDestinationAddImage(gif, image, frame)
                count += 1
            }
        }
        guard CGImageDestinationFinalize(gif) else { print("failed to finish GIF"); exit(1) }
        let size = (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
        print(String(format: "%@: %d frames, %.1f MB", output.lastPathComponent, count, Double(size) / 1_048_576))
        if size > 8_000_000 { print("tip: that's big for a README — try a smaller width (720) or fps (12), or trim with start/end") }
    } catch {
        print("error: \(error.localizedDescription)"); exit(1)
    }
    done.signal()
}
done.wait()
