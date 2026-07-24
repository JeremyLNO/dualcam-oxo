import SwiftUI
import CrazyBeeLicense

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
        // -skipOnboarding marks first-launch onboarding as already done (screenshots/UI tests).
        if args.contains("-skipOnboarding") {
            UserDefaults.standard.set(true, forKey: RootView.onboardingKey)
        }
        ReviewManager.shared.bootstrap()   // stamp the install date on first run
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .task {
                    // Silent update check on launch (fires a local notice if newer exists).
                    await NotificationService.shared.checkForUpdate()
                }
        }
    }
}

/// Shows the first-launch onboarding carousel once, then falls through to `AppGate`
/// (unchanged) for every later launch.
private struct RootView: View {
    static let onboardingKey = "onboarding.completed"

    @AppStorage(onboardingKey) private var onboardingCompleted = false

    var body: some View {
        if onboardingCompleted {
            AppGate()
        } else {
            OnboardingView { onboardingCompleted = true }
        }
    }
}

/// Gates the whole app behind the license state — trial running or a valid license
/// shows `CameraView`, otherwise the shared `LicenseLockedView` paywall.
private struct AppGate: View {
    @ObservedObject private var license = AppLicense.manager

    var body: some View {
        Group {
            if license.isFunctional {
                CameraView()
            } else {
                LicenseLockedView(
                    manager: license,
                    features: AppLicense.features,
                    logo: Image("CrazyBeeLabsLogo")
                )
            }
        }
        .task { await license.refresh() }
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
