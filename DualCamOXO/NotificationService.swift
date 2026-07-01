import Foundation
import UserNotifications
import UIKit

/// Push + local notifications.
///
/// Remote push is delivered through **OneSignal** (https://onesignal.com). The SDK
/// is optional at build time so the app compiles and runs without it: once you add
/// the `OneSignalXCFramework` Swift Package and set `oneSignalAppID`, the guarded
/// block below wires it up. Messages and their deep links are authored in the
/// OneSignal dashboard (or via its REST API) — including the "update available"
/// campaign.
///
/// A local fallback (`checkForUpdate`) also fires an on-device notification when the
/// App Store lists a newer version, so update alerts work even before push is set up.
@MainActor
final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    /// Paste your OneSignal App ID here (dashboard → Settings → Keys & IDs).
    static let oneSignalAppID = ""

    @Published var authorized = false

    /// Called once at launch. Registers OneSignal if present, and syncs auth state.
    func configure(launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) {
        UNUserNotificationCenter.current().delegate = self
        refreshAuthorization()

        #if canImport(OneSignalFramework)
        if !Self.oneSignalAppID.isEmpty {
            OneSignalBridge.initialize(appID: Self.oneSignalAppID, launchOptions: launchOptions)
        }
        #endif
    }

    /// Ask for permission (used by the Settings toggle).
    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await MainActor.run { self.authorized = granted }
        #if canImport(OneSignalFramework)
        if granted { OneSignalBridge.promptForPush() }
        #endif
        return granted
    }

    func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            Task { @MainActor in self.authorized = (s.authorizationStatus == .authorized) }
        }
    }

    // MARK: - Local "update available" check (works without push)

    /// Compares the App Store version to the installed one and, if newer, posts a
    /// local notification with a deep link to the store page.
    /// Returns the newer version string if an update exists.
    @discardableResult
    func checkForUpdate() async -> String? {
        // Skip when no App Store ID is wired yet.
        guard AppInfo.appStoreID != "0000000000" else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: AppInfo.lookupURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let store = results.first?["version"] as? String else { return nil }

        guard isNewer(store, than: AppInfo.shortVersion) else { return nil }
        if authorized { postUpdateNotification(version: store) }
        return store
    }

    private func postUpdateNotification(version: String) {
        let content = UNMutableNotificationContent()
        content.title = L.t("update_available")
        content.body = "DualCam OxO \(version)"
        content.sound = .default
        content.userInfo = ["url": "https://apps.apple.com/app/id\(AppInfo.appStoreID)"]
        let req = UNNotificationRequest(identifier: "update.\(version)", content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }

    /// Semantic-ish version compare ("1.2.0" vs "1.10.0").
    private func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    // Show notifications while the app is foregrounded.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler:
                                            @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Follow the notification's deep link (App Store page, in-app screen, etc.).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let s = info["url"] as? String, let url = URL(string: s) {
            Task { @MainActor in UIApplication.shared.open(url) }
        }
        completionHandler()
    }
}
