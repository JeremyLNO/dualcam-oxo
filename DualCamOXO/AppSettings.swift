import SwiftUI
import Combine

/// Central, versioned user preferences.
///
/// All values are persisted in `UserDefaults` under stable keys. A `schemaVersion`
/// gate lets future releases migrate old installs *without losing data*: unknown
/// future keys are ignored, missing keys fall back to sane defaults, and the
/// migration step only ever *adds* defaults — it never clears what the user set.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let d = UserDefaults.standard
    private enum Key {
        static let schema        = "settings.schemaVersion"
        static let mode          = "capture.mode"
        static let side          = "capture.side"
        static let quality       = "capture.quality"
        static let saveMode      = "save.mode"
        static let grid          = "ui.grid"
        static let flashDefault  = "capture.flashDefault"
        static let notifications = "notif.enabled"
    }
    /// Bump when the persisted shape changes; add a migration branch below.
    static let currentSchema = 1

    @Published var mode: CaptureMode        { didSet { d.set(mode.rawValue, forKey: Key.mode) } }
    @Published var side: CameraSide         { didSet { d.set(side.rawValue, forKey: Key.side) } }
    @Published var quality: VideoQuality    { didSet { d.set(quality.rawValue, forKey: Key.quality) } }
    @Published var saveMode: SaveMode       { didSet { d.set(saveMode.rawValue, forKey: Key.saveMode) } }
    @Published var showGrid: Bool           { didSet { d.set(showGrid, forKey: Key.grid) } }
    @Published var flashDefault: Bool       { didSet { d.set(flashDefault, forKey: Key.flashDefault) } }
    @Published var notificationsEnabled: Bool { didSet { d.set(notificationsEnabled, forKey: Key.notifications) } }

    private init() {
        // Read with fallbacks so a fresh or partially-written store is always valid.
        mode         = CameraModelsDecode.mode(d.string(forKey: Key.mode))
        side         = CameraSide(rawValue: d.string(forKey: Key.side) ?? "") ?? .back
        quality      = VideoQuality(rawValue: d.string(forKey: Key.quality) ?? "") ?? .hd1080
        saveMode     = SaveMode(rawValue: d.string(forKey: Key.saveMode) ?? "") ?? .combined
        showGrid     = d.object(forKey: Key.grid) as? Bool ?? false
        flashDefault = d.object(forKey: Key.flashDefault) as? Bool ?? false
        notificationsEnabled = d.object(forKey: Key.notifications) as? Bool ?? true
        migrateIfNeeded()
    }

    /// Forward-compatible migration. Never destructive.
    private func migrateIfNeeded() {
        let stored = d.integer(forKey: Key.schema)   // 0 when absent
        guard stored < AppSettings.currentSchema else { return }
        // v0 → v1: nothing to rewrite; just stamp the schema so defaults persist.
        // Future: `if stored < 2 { … }`
        d.set(AppSettings.currentSchema, forKey: Key.schema)
    }
}

/// Small helper kept separate so `AppSettings.init` stays declarative.
private enum CameraModelsDecode {
    static func mode(_ raw: String?) -> CaptureMode {
        CaptureMode(rawValue: raw ?? "") ?? .frontBack
    }
}
