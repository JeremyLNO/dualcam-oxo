import SwiftUI

@main
struct DualCamOXOApp: App {
    @StateObject private var settings = AppSettings.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // -demoLang <en|fr|es|de|pt> forces the UI language (deterministic screenshots).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-demoLang"), i + 1 < args.count {
            UserDefaults.standard.set(args[i + 1], forKey: AppLanguage.storageKey)
        }
        // -demoMode <orientation|frontBack> forces the capture mode (screenshots).
        if let i = args.firstIndex(of: "-demoMode"), i + 1 < args.count,
           CaptureMode(rawValue: args[i + 1]) != nil {
            UserDefaults.standard.set(args[i + 1], forKey: "capture.mode")
        }
        ReviewManager.shared.bootstrap()   // stamp the install date on first run
    }

    var body: some Scene {
        WindowGroup {
            CameraView()
                .environmentObject(settings)
                .task {
                    // Silent update check on launch (fires a local notice if newer exists).
                    await NotificationService.shared.checkForUpdate()
                }
        }
    }
}

/// Handles push/OneSignal setup at process launch.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
                     [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationService.shared.configure(launchOptions: launchOptions)
        return true
    }
}
