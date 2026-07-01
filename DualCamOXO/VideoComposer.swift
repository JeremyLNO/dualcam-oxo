import AVFoundation
import Photos
import UIKit

/// Turns a finished `CameraEngine.Take` into what the user asked for in Settings:
/// either two separate clips saved to Photos, or one combined (stacked) clip.
enum VideoComposer {

    enum ComposerError: Error { case export, noTracks }

    /// Save both feeds to Photos according to `mode`.
    static func save(take a: URL, and b: URL, as mode: SaveMode) async throws {
        try await ensurePhotoPermission()
        switch mode {
        case .separate:
            try await addToPhotos(a)
            try await addToPhotos(b)
        case .combined:
            let merged = try await combine(top: a, bottom: b)
            try await addToPhotos(merged)
        }
    }

    // MARK: - Combine (stacked, portrait canvas)

    static func combine(top: URL, bottom: URL) async throws -> URL {
        let topAsset = AVURLAsset(url: top)
        let botAsset = AVURLAsset(url: bottom)

        guard let topV = try await topAsset.loadTracks(withMediaType: .video).first,
              let botV = try await botAsset.loadTracks(withMediaType: .video).first
        else { throw ComposerError.noTracks }

        let comp = AVMutableComposition()
        guard let ct = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let cb = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ComposerError.export }

        let dur = try await topAsset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: dur)
        try ct.insertTimeRange(range, of: topV, at: .zero)
        try? cb.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: botV, at: .zero)

        // Add the first available audio track.
        if let aTrack = try await topAsset.loadTracks(withMediaType: .audio).first,
           let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? ca.insertTimeRange(range, of: aTrack, at: .zero)
        }

        // Each feed is portrait; stack them into a taller portrait canvas.
        let topSize = try await naturalOriented(topV)
        let cellW = topSize.width
        let cellH = topSize.height
        let canvas = CGSize(width: cellW, height: cellH * 2)

        let li1 = AVMutableVideoCompositionLayerInstruction(assetTrack: ct)
        li1.setTransform(try await transform(for: topV, in: CGRect(x: 0, y: 0, width: cellW, height: cellH)), at: .zero)
        let li2 = AVMutableVideoCompositionLayerInstruction(assetTrack: cb)
        li2.setTransform(try await transform(for: botV, in: CGRect(x: 0, y: cellH, width: cellW, height: cellH)), at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = range
        instruction.layerInstructions = [li1, li2]

        let vComp = AVMutableVideoComposition()
        vComp.renderSize = canvas
        vComp.frameDuration = CMTime(value: 1, timescale: 30)
        vComp.instructions = [instruction]

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

    /// Natural size accounting for the track's preferred transform.
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
}
