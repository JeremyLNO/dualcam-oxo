import AVFoundation
import SwiftUI

/// The two ways DualCam OxO films with two lenses at once.
enum CaptureMode: String, CaseIterable, Identifiable, Codable {
    /// Two lenses on the *same* side (back or front): one framed portrait, one landscape.
    case orientation
    /// Front and back cameras together.
    case frontBack
    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .orientation: return "mode_orientation"
        case .frontBack:   return "mode_frontback"
        }
    }
    var icon: String {
        switch self {
        case .orientation: return "rectangle.portrait.on.rectangle.portrait.angled"
        case .frontBack:   return "arrow.triangle.2.circlepath.camera"
        }
    }
}

/// Which physical side the `orientation` mode uses.
enum CameraSide: String, CaseIterable, Identifiable, Codable {
    case back, front
    var id: String { rawValue }
    var titleKey: String { self == .back ? "side_back" : "side_front" }
    var avPosition: AVCaptureDevice.Position { self == .back ? .back : .front }
}

/// Recording resolution.
enum VideoQuality: String, CaseIterable, Identifiable, Codable {
    case hd720, hd1080, uhd4k
    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .hd720:  return "quality_720"
        case .hd1080: return "quality_1080"
        case .uhd4k:  return "quality_4k"
        }
    }
    var shortLabel: String {
        switch self {
        case .hd720:  return "720p"
        case .hd1080: return "1080p"
        case .uhd4k:  return "4K"
        }
    }
    /// Target pixel dimensions (portrait-oriented height×width handled by the writer).
    var dimensions: CGSize {
        switch self {
        case .hd720:  return CGSize(width: 1280, height: 720)
        case .hd1080: return CGSize(width: 1920, height: 1080)
        case .uhd4k:  return CGSize(width: 3840, height: 2160)
        }
    }
    var bitrate: Int {
        switch self {
        case .hd720:  return 6_000_000
        case .hd1080: return 12_000_000
        case .uhd4k:  return 44_000_000
        }
    }
}

/// Still photo vs. video capture.
enum CaptureKind: String, CaseIterable, Identifiable, Codable {
    case video, photo
    var id: String { rawValue }
    var titleKey: String { self == .video ? "video" : "photo" }
    var icon: String { self == .video ? "video.fill" : "camera.fill" }
}

/// How a *combined* export arranges the two feeds.
enum CombinedLayout: String, CaseIterable, Identifiable, Codable {
    /// Feeds stacked one above the other.
    case stacked
    /// Secondary feed inset over the primary (matches the on-screen preview).
    case pip
    var id: String { rawValue }
    var titleKey: String { self == .stacked ? "layout_stacked" : "layout_pip" }
    var icon: String { self == .stacked ? "rectangle.split.1x2" : "rectangle.inset.bottomright.filled" }
}

/// How the two feeds land in Photos.
enum SaveMode: String, CaseIterable, Identifiable, Codable {
    /// Both feeds composited (stacked) into a single video.
    case combined
    /// Each feed exported as its own video.
    case separate
    var id: String { rawValue }
    var titleKey: String { self == .combined ? "save_combined" : "save_separate" }
    var descKey: String  { self == .combined ? "save_combined_desc" : "save_separate_desc" }
    var icon: String     { self == .combined ? "rectangle.split.1x2" : "square.on.square" }
}
