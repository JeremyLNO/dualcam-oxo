#if DEBUG
import AVFoundation
import UIKit

/// Throwaway diagnostic for the "combined video is black" bug.
/// Writes `Documents/combine.log` and copies the three clips (A, B, combined)
/// next to it, so they can be pulled off the device with `devicectl` and
/// replayed on the Mac. Compiled out of Release builds; delete once fixed.
enum CombineDiag {

    /// Off unless the app is launched with `-diagCombine`. Keeps the hooks in the
    /// Debug build at zero cost, one flag away if the black-combined bug returns.
    static let enabled = CommandLine.arguments.contains("-diagCombine")

    private static let q = DispatchQueue(label: "com.crazybeelabs.dualcam.diag")
    private static var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var logURL: URL { docs.appendingPathComponent("combine.log") }

    static func reset() {
        guard enabled else { return }
        q.sync {
            try? FileManager.default.removeItem(at: logURL)
            FileManager.default.createFile(atPath: logURL.path, contents: Data())
        }
    }

    static func log(_ line: String) {
        guard enabled else { return }
        q.sync {
            let stamped = "[\(String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 10000)))] \(line)\n"
            if let h = try? FileHandle(forWritingTo: logURL) {
                h.seekToEndOfFile(); h.write(Data(stamped.utf8)); try? h.close()
            } else {
                try? stamped.write(to: logURL, atomically: true, encoding: .utf8)
            }
            NSLog("DIAG %@", line)
        }
    }

    /// Copies `url` into Documents under `name` so it can be retrieved later.
    static func keep(_ url: URL, as name: String) {
        guard enabled else { return }
        let dst = docs.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dst)
        do {
            try FileManager.default.copyItem(at: url, to: dst)
            let size = (try? FileManager.default.attributesOfItem(atPath: dst.path)[.size] as? Int) ?? 0
            log("gardé \(name) — \(size ?? 0) octets")
        } catch {
            log("copie \(name) IMPOSSIBLE : \(error)")
        }
    }

    /// Everything that could make a composition render black, for one source file.
    static func describe(_ url: URL, tag: String) async {
        guard enabled else { return }
        let asset = AVURLAsset(url: url)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard let v = (try? await asset.loadTracks(withMediaType: .video))?.first else {
            log("\(tag): AUCUNE PISTE VIDÉO (fichier \(size ?? 0) o) ← moov absent / writer non finalisé")
            return
        }
        let dur = (try? await asset.load(.duration))?.seconds ?? -1
        let ns = (try? await v.load(.naturalSize)) ?? .zero
        let tf = (try? await v.load(.preferredTransform)) ?? .identity
        let tr = try? await v.load(.timeRange)
        let fps = (try? await v.load(.nominalFrameRate)) ?? 0
        var codec = "?"
        if let fds = try? await v.load(.formatDescriptions), let f = fds.first {
            let c = CMFormatDescriptionGetMediaSubType(f)
            codec = String(bytes: [UInt8((c >> 24) & 0xff), UInt8((c >> 16) & 0xff),
                                   UInt8((c >> 8) & 0xff), UInt8(c & 0xff)], encoding: .ascii) ?? "?"
            let d = CMVideoFormatDescriptionGetDimensions(f)
            codec += " \(d.width)x\(d.height)"
            if let ext = CMFormatDescriptionGetExtensions(f) as? [String: Any] {
                for k in ["ColorPrimaries", "TransferFunction", "YCbCrMatrix", "FullRangeVideo"] {
                    if let val = ext[k] { codec += " \(k)=\(val)" }
                }
            }
        }
        let audio = ((try? await asset.loadTracks(withMediaType: .audio)) ?? []).count
        log("""
            \(tag): \(size ?? 0) o  natural=\(Int(ns.width))x\(Int(ns.height))  \
            tf=[\(tf.a) \(tf.b) \(tf.c) \(tf.d) \(tf.tx) \(tf.ty)]  \
            durée=\(String(format: "%.2f", dur))  \
            piste=[\(String(format: "%.2f", tr?.start.seconds ?? -1))→\(String(format: "%.2f", tr?.duration.seconds ?? -1))]  \
            fps=\(String(format: "%.1f", fps))  \(codec)  audio=\(audio)  luma=\(await luma(url))
            """)
    }

    /// Mean luma of a frame taken 25% into the clip. `-1` when it cannot be read.
    /// A value near 0 means the frame really is black.
    static func luma(_ url: URL) async -> String {
        let asset = AVURLAsset(url: url)
        guard let dur = try? await asset.load(.duration), dur.seconds > 0 else { return "n/a" }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        let t = CMTime(seconds: dur.seconds * 0.25, preferredTimescale: 600)
        guard let cg = try? await gen.image(at: t).image else { return "ILLISIBLE" }
        let w = 32, h = 32
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return "n/a" }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            sum += 0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])
        }
        return String(format: "%.1f", sum / Double(w * h))
    }
}
#endif
