import SwiftUI

// MARK: - App info / links

enum AppInfo {
    /// "Support & ideas" destination (web page).
    static let supportURL = URL(string: "https://crazybeelabs.com/support/")!
    /// Crazy Bee Labs website.
    static let siteURL = URL(string: "https://crazybeelabs.com/")!
    /// Account sign-up on the Crazy Bee Labs site.
    static let signUpURL = URL(string: "https://crazybeelabs.com/account/")!
    /// Privacy policy, required by App Review whenever an app collects any data.
    static let privacyPolicyURL = URL(string: "https://www.crazybeelabs.com/legal/apps")!

    /// Base URL of the Crazy Bee Labs account API (crazybeelabs-app).
    static let apiBaseURL = URL(string: "https://www.crazybeelabs.com/api")!

    /// App Store numeric ID — fill in once the app is live on the App Store.
    /// Until then the review "Yes" button falls back to the CBL site.
    static let appStoreID = "0000000000"

    /// Deep link that opens the App Store review sheet.
    static var appStoreReviewURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
            ?? siteURL
    }
    /// iTunes lookup endpoint used to detect a newer published version.
    static var lookupURL: URL {
        URL(string: "https://itunes.apple.com/lookup?id=\(appStoreID)")!
    }

    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    static var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    static var versionString: String { "\(shortVersion) (\(buildVersion))" }
}

// MARK: - Reusable UI

/// A frosted dark panel used for control clusters over the camera.
struct GlassPanel<Content: View>: View {
    var content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

/// A pill-shaped segmented switch bound to a hashable value.
struct SegmentedPills<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { opt in
                let active = opt.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.18)) { selection = opt.value }
                } label: {
                    Text(opt.label)
                        .font(.footnote.weight(.semibold))
                        .padding(.vertical, 8).padding(.horizontal, 12)
                        .foregroundStyle(active ? Color.black : Palette.ink)
                        .background {
                            if active {
                                Capsule().fill(LinearGradient.honey)
                            } else {
                                Capsule().fill(Color.white.opacity(0.06))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.35)))
    }
}

/// Transient toast overlay.
struct Toast: View {
    let text: String
    var systemImage: String = "checkmark.circle.fill"
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .padding(.vertical, 10).padding(.horizontal, 16)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}

extension View {
    /// Dismiss the keyboard from anywhere.
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
