import SwiftUI
import CrazyBeeLicense

/// First-launch onboarding: a paged carousel of the app's headline features (same copy
/// as the paywall's `AppLicense.features`) followed by a page confirming the 7-day free
/// trial has started with every feature unlocked and no payment info needed.
///
/// Shown once, gated by `onboarding.completed` in `UserDefaults` (see `RootView` in
/// `DualCamOXOApp.swift`). Deliberately touches nothing camera-related — the camera/mic
/// permission prompt still only fires when `CameraView` appears afterwards.
struct OnboardingView: View {
    let onFinished: () -> Void

    @State private var page = 0
    private let lang = AppLanguage.current
    private var features: [LicenseFeature] { AppLicense.features }

    var body: some View {
        ZStack {
            LinearGradient.appBackground.ignoresSafeArea()

            TabView(selection: $page) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    OnboardingFeaturePage(feature: feature)
                        .tag(index)
                }
                OnboardingTrialPage(lang: lang, onContinue: onFinished)
                    .tag(features.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }
}

/// One feature highlight page (icon + title + detail), reusing `LicenseFeature` content.
private struct OnboardingFeaturePage: View {
    let feature: LicenseFeature

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: feature.systemImage)
                .font(.system(size: 52))
                .foregroundStyle(LinearGradient.honey)
                .frame(width: 108, height: 108)
                .background(Palette.honeySoft, in: Circle())

            Text(feature.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)

            Text(feature.detail)
                .font(.body)
                .foregroundStyle(Palette.sub)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
            Spacer() // leave room for the page-dot indicator
        }
        .padding(.horizontal, 24)
    }
}

/// Final page: the trial has started, everything is unlocked, no card needed.
private struct OnboardingTrialPage: View {
    let lang: AppLanguage
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(LinearGradient.honey)
                .frame(width: 108, height: 108)
                .background(Palette.honeySoft, in: Circle())

            Text(L.t("onboarding_trial_title", lang))
                .font(.title2.weight(.bold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)

            Text(L.t("onboarding_trial_body", lang))
                .font(.body)
                .foregroundStyle(Palette.sub)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button(action: onContinue) {
                Text(L.t("onboarding_get_started", lang))
                    .font(.headline).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(LinearGradient.honey, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 24)
    }
}
