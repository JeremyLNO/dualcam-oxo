import Foundation
import UIKit

// The OneSignal Swift Package (`OneSignal-XCFramework`, pinned to 5.5.1) is linked
// into the app target, so this file compiles for real; it stays inert at runtime
// until `NotificationService.oneSignalAppID` holds an actual App ID.
#if canImport(OneSignalFramework)
import OneSignalFramework

enum OneSignalBridge {
    static func initialize(appID: String, launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        OneSignal.initialize(appID, withLaunchOptions: launchOptions)
        // Deep links carried in a push land here (open App Store / in-app screen).
        OneSignal.Notifications.addClickListener(ClickListener())
    }

    static func promptForPush() {
        OneSignal.Notifications.requestPermission({ _ in }, fallbackToSettings: true)
    }

    final class ClickListener: NSObject, OSNotificationClickListener {
        func onClick(event: OSNotificationClickEvent) {
            let data = event.notification.additionalData
            if let s = data?["url"] as? String, let url = URL(string: s) {
                DispatchQueue.main.async { UIApplication.shared.open(url) }
            }
        }
    }
}
#endif
