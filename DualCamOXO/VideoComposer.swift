import AVFoundation
import Photos
import UIKit

/// Turns a finished capture into what the user asked for in Settings:
/// two separate items, or one combined item (stacked or picture-in-picture).
enum VideoComposer {

    enum ComposerError: Error { case export, noTracks }

    // MARK: - Video

    /// Save both video feeds to Photos according to `mode` / `layout`.
    /// `watermarked` marks the free-tier "DualCam OxO" stamp on the combined
    /// output only — the two raw separate clips are never watermarked.
    static func save(take a: URL, and b: URL, as mode: SaveMode, layout: CombinedLayout,
                     watermarked: Bool) async throws {
        try await ensurePhotoPermission()
        switch mode {
        case .separate:
            try await addToPhotos(a); try await addToPhotos(b)
        case .combined:
            let merged = try await combine(main: a, secondary: b, layout: layout, watermarked: watermarked)
            try await addToPhotos(merged)
        }
    }

    /// Compose the two clips into one, either stacked or with the secondary inset (PiP).
    static func combine(main: URL, secondary: URL, layout: CombinedLayout,
                        watermarked: Bool = false) async throws -> URL {
        let mainAsset = AVURLAsset(url: main)
        let secAsset  = AVURLAsset(url: secondary)

        guard let mainV = try await mainAsset.loadTracks(withMediaType: .video).first,
              let secV  = try await secAsset.loadTracks(withMediaType: .video).first
        else { throw ComposerError.noTracks }

        let comp = AVMutableComposition()
        guard let cm = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let cs = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ComposerError.export }

        let dur = try await mainAsset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: dur)
        try cm.insertTimeRange(range, of: mainV, at: .zero)
        try? cs.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: secV, at: .zero)

        if let aTrack = try await mainAsset.loadTracks(withMediaType: .audio).first,
           let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? ca.insertTimeRange(range, of: aTrack, at: .zero)
        }

        let mainSize = try await naturalOriented(mainV)
        let secSize  = try await naturalOriented(secV)

        let canvas: CGSize
        let mainRect: CGRect
        let secRect: CGRect
        switch layout {
        case .stacked:
            let w = mainSize.width, h = mainSize.height
            canvas   = CGSize(width: w, height: h * 2)
            mainRect = CGRect(x: 0, y: 0, width: w, height: h)
            secRect  = CGRect(x: 0, y: h, width: w, height: h)
        case .pip:
            canvas = mainSize
            mainRect = CGRect(origin: .zero, size: mainSize)
            let insetW = mainSize.width * 0.32
            let insetH = insetW * (secSize.height / max(secSize.width, 1))
            let margin = mainSize.width * 0.04
            secRect = CGRect(x: canvas.width - insetW - margin, y: margin, width: insetW, height: insetH)
        }

        let liMain = AVMutableVideoCompositionLayerInstruction(assetTrack: cm)
        liMain.setTransform(try await transform(for: mainV, in: mainRect), at: .zero)
        let liSec = AVMutableVideoCompositionLayerInstruction(assetTrack: cs)
        liSec.setTransform(try await transform(for: secV, in: secRect), at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = range
        // First layer instruction renders in front, so the inset goes first for PiP.
        instruction.layerInstructions = (layout == .pip) ? [liSec, liMain] : [liMain, liSec]

        let vComp = AVMutableVideoComposition()
        vComp.renderSize = canvas
        vComp.frameDuration = CMTime(value: 1, timescale: 30)
        vComp.instructions = [instruction]
        if watermarked {
            vComp.animationTool = watermarkAnimationTool(canvas: canvas)
        }

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("dualcam_combined_\(Int(Date().timeIntervalSince1970)).mov")
        try? FileManager.default.removeItem(at: out)

        guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)
        else { throw ComposerError.export }
        export.outputURL = out
        export.outputFileType = .mov
        export.videoComposition = vComp
        await export.export()
        guard export.status == .completed else { throw export.error ?? ComposerError.export }
        return out
    }

    /// Burns a small "DualCam OxO" stamp into the bottom-right corner via a Core
    /// Animation overlay — the standard way to composite a CALayer into an export.
    private static func watermarkAnimationTool(canvas: CGSize) -> AVVideoCompositionCoreAnimationTool {
        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: canvas)

        let videoLayer = CALayer()
        videoLayer.frame = overlayLayer.frame
        overlayLayer.addSublayer(videoLayer)

        let fontSize = canvas.width * 0.026
        let textLayer = CATextLayer()
        textLayer.string = "DualCam OxO"
        textLayer.font = UIFont.boldSystemFont(ofSize: fontSize)
        textLayer.fontSize = fontSize
        textLayer.alignmentMode = .right
        textLayer.foregroundColor = UIColor.white.withAlphaComponent(0.85).cgColor
        textLayer.shadowColor = UIColor.black.cgColor
        textLayer.shadowOpacity = 0.6
        textLayer.shadowRadius = 3
        textLayer.shadowOffset = .zero
        textLayer.contentsScale = 2
        let margin = canvas.width * 0.035
        textLayer.frame = CGRect(x: 0, y: canvas.height - fontSize * 1.6 - margin,
                                 width: canvas.width - margin, height: fontSize * 1.6)
        overlayLayer.addSublayer(textLayer)

        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: overlayLayer)
    }

    private static func naturalOriented(_ track: AVAssetTrack) async throws -> CGSize {
        let size = try await track.load(.naturalSize)
        let t = try await track.load(.preferredTransform)
        let r = size.applying(t)
        return CGSize(width: abs(r.width), height: abs(r.height))
    }

    /// A transform that draws `track` upright, aspect-fill, inside `rect`.
    private static func transform(for track: AVAssetTrack, in rect: CGRect) async throws -> CGAffineTransform {
        let natural = try await track.load(.naturalSize)
        let pref = try await track.load(.preferredTransform)
        let oriented = natural.applying(pref)
        let ow = abs(oriented.width), oh = abs(oriented.height)
        let scale = max(rect.width / ow, rect.height / oh)
        let tx = rect.minX + (rect.width - ow * scale) / 2
        let ty = rect.minY + (rect.height - oh * scale) / 2
        return pref.concatenating(CGAffineTransform(scaleX: scale, y: scale))
                   .concatenating(CGAffineTransform(translationX: tx, y: ty))
    }

    // MARK: - Photo

    /// Save both still images to Photos according to `mode` / `layout`.
    static func savePhotos(_ a: UIImage, _ b: UIImage, mode: SaveMode, layout: CombinedLayout,
                           watermarked: Bool) async throws {
        try await ensurePhotoPermission()
        switch mode {
        case .separate:
            try await addImageToPhotos(a); try await addImageToPhotos(b)
        case .combined:
            try await addImageToPhotos(
                composePhoto(main: a, secondary: b, layout: layout, watermarked: watermarked))
        }
    }

    private static func composePhoto(main: UIImage, secondary: UIImage, layout: CombinedLayout,
                                     watermarked: Bool) -> UIImage {
        let canvas: CGSize = (layout == .stacked)
            ? CGSize(width: main.size.width, height: main.size.height * 2)
            : main.size
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            switch layout {
            case .stacked:
                let h = main.size.height
                drawAspectFill(main, in: CGRect(x: 0, y: 0, width: canvas.width, height: h), ctx)
                drawAspectFill(secondary, in: CGRect(x: 0, y: h, width: canvas.width, height: h), ctx)
            case .pip:
                drawAspectFill(main, in: CGRect(origin: .zero, size: canvas), ctx)
                let insetW = canvas.width * 0.32
                let insetH = insetW * (secondary.size.height / max(secondary.size.width, 1))
                let margin = canvas.width * 0.04
                let rect = CGRect(x: canvas.width - insetW - margin, y: margin, width: insetW, height: insetH)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: insetW * 0.08)
                ctx.cgContext.saveGState()
                path.addClip()
                drawAspectFill(secondary, in: rect, ctx)
                ctx.cgContext.restoreGState()
                UIColor(white: 1, alpha: 0.9).setStroke()
                path.lineWidth = max(2, insetW * 0.02)
                path.stroke()
            }
            if watermarked { drawWatermark(in: canvas) }
        }
    }

    /// Draws the free-tier "DualCam OxO" stamp in the bottom-right corner.
    private static func drawWatermark(in canvas: CGSize) {
        let fontSize = canvas.width * 0.026
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: UIColor.white.withAlphaComponent(0.85),
            .shadow: {
                let s = NSShadow()
                s.shadowColor = UIColor.black.withAlphaComponent(0.6)
                s.shadowBlurRadius = 3
                return s
            }(),
        ]
        let text = "DualCam OxO" as NSString
        let size = text.size(withAttributes: attrs)
        let margin = canvas.width * 0.035
        let origin = CGPoint(x: canvas.width - size.width - margin, y: canvas.height - size.height - margin)
        text.draw(at: origin, withAttributes: attrs)
    }

    private static func drawAspectFill(_ image: UIImage, in rect: CGRect, _ ctx: UIGraphicsImageRendererContext) {
        ctx.cgContext.saveGState()
        ctx.cgContext.clip(to: rect)
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let w = image.size.width * scale, h = image.size.height * scale
        image.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
        ctx.cgContext.restoreGState()
    }

    // MARK: - Photos

    private static func ensurePhotoPermission() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited: return
        case .notDetermined:
            let new = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard new == .authorized || new == .limited else { throw ComposerError.export }
        default: throw ComposerError.export
        }
    }

    private static func addToPhotos(_ url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
        }
    }

    private static func addImageToPhotos(_ image: UIImage) async throws {
        guard let data = image.jpegData(compressionQuality: 0.95) else { throw ComposerError.export }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }
}
