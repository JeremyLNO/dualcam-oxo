import Foundation
import CrazyBeeLicense

/// Wires the shared CrazyBeeLicense package to this app's bundle id + purchase page.
/// Same pattern as Shotbox / Macnap Blocker / Energy Manager / SpacesPilot / Record Seconds.
enum AppLicense {
    @MainActor static let manager = LicenseManager(config: .init(
        apiBaseURL: URL(string: "https://crazybeelabs.com")!,
        bundleId: "company.lno.dualcamoxo",
        purchaseURL: URL(string: "https://crazybeelabs.com/apps/dualcam-oxo")!
    ))

    @MainActor static var features: [LicenseFeature] {
        [
            LicenseFeature(
                systemImage: "4k.circle.fill",
                title: L.t("license_feature_4k_title", lang),
                detail: L.t("license_feature_4k_detail", lang)
            ),
            LicenseFeature(
                systemImage: "square.on.square",
                title: L.t("license_feature_layouts_title", lang),
                detail: L.t("license_feature_layouts_detail", lang)
            ),
            LicenseFeature(
                systemImage: "checkmark.seal.fill",
                title: L.t("license_feature_nowatermark_title", lang),
                detail: L.t("license_feature_nowatermark_detail", lang)
            ),
        ]
    }

    private static var lang: AppLanguage { AppLanguage.current }
}
