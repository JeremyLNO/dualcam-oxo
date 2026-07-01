import SwiftUI

/// Drives the "Are you enjoying DualCam OxO?" prompt shown ~24h after install.
///
/// Flow (iOS): **Yes** → App Store rating page · **No** → Support & ideas page.
/// The install date and "already asked" flag are persisted so the prompt appears
/// exactly once and survives upgrades.
@MainActor
final class ReviewManager: ObservableObject {
    static let shared = ReviewManager()

    private let d = UserDefaults.standard
    private enum Key {
        static let installDate = "review.installDate"
        static let asked       = "review.asked"
    }
    /// Delay before asking. 24h in production; overridable for testing.
    static let delay: TimeInterval = 24 * 60 * 60

    @Published var isPresented = false

    /// Record the install timestamp the very first time the app runs.
    func bootstrap() {
        if d.object(forKey: Key.installDate) == nil {
            d.set(Date(), forKey: Key.installDate)
        }
    }

    /// Show the prompt if enough time has passed and we haven't asked yet.
    /// `-forceReview` (launch arg) shows it immediately for screenshots/testing.
    func evaluate(force: Bool = false) {
        if force { isPresented = true; return }
        guard !d.bool(forKey: Key.asked),
              let install = d.object(forKey: Key.installDate) as? Date,
              Date().timeIntervalSince(install) >= Self.delay else { return }
        isPresented = true
    }

    func handle(happy: Bool) {
        d.set(true, forKey: Key.asked)
        isPresented = false
        let url = happy ? AppInfo.appStoreReviewURL : AppInfo.supportURL
        UIApplication.shared.open(url)
    }

    func dismiss() {
        // Dismissed without choosing: don't nag again.
        d.set(true, forKey: Key.asked)
        isPresented = false
    }
}
