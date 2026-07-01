import Foundation
import UIKit

// This whole file is inert until the OneSignal Swift Package is added to the target.
// Add `OneSignalXCFramework` (https://github.com/OneSignal/OneSignal-iOS-SDK) via
// Swift Package Manager, then set `NotificationService.oneSignalAppID`.
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
