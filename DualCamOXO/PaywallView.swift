import SwiftUI
import StoreKit

/// DualCam OxO Pro paywall — **In-App Purchase only** (App Review 3.1.1: on iOS,
/// paid features can't be unlocked by a licence bought on the web the way the
/// macOS apps do).
///
/// Layout puts the product first: app icon + name at the top, the offer in the
/// middle, and the Crazy Bee Labs logo at the bottom as a signature.
struct PaywallView: View {
    /// `true` when shown as the trial-expired gate (no close button — the app is locked).
    var isGate: Bool = false

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ProStore.shared
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.systemDefault.rawValue
    private var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .en }

    @State private var busy = false

    var body: some View {
        ZStack {
            LinearGradient.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    appHeader
                    headline.padding(.top, 24)
                    features.padding(.top, 22)
                    offer.padding(.top, 22)
                    callToAction.padding(.top, 18)
                    legal.padding(.top, 16)
                    signature.padding(.top, 28)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 26)
            }
            if busy {
                Color.black.opacity(0.45).ignoresSafeArea()
                ProgressView(L.t("pay_processing", lang))
                    .tint(Palette.honey)
                    .foregroundStyle(Palette.ink)
                    .padding(22)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .topTrailing) {
            if !isGate {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Palette.faint)
                }
                .padding(.trailing, 18)
                .padding(.top, 10)
            }
        }
        .task { if store.hasNoProducts { await store.load() } }
        .onChange(of: store.isPro) { _, pro in if pro, !isGate { dismiss() } }
    }

    // MARK: - App identity (top priority)

    private var appHeader: some View {
        VStack(spacing: 12) {
            Image("AppIconDisplay")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Palette.honey.opacity(0.25), radius: 16, y: 8)

            Text("DualCam OxO")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.ink)

            Text(L.t("app_tagline", lang))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Palette.sub)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, isGate ? 40 : 18)
    }

    private var headline: some View {
        VStack(spacing: 6) {
            Text(isGate ? L.t("pay_trial_ended", lang) : L.t("pay_get_pro", lang))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text(L.t("pay_subtitle", lang))
                .font(.subheadline)
                .foregroundStyle(Palette.sub)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Features

    private var features: some View {
        VStack(spacing: 14) {
            featureRow("4k.tv.fill", L.t("license_feature_4k_title", lang), L.t("license_feature_4k_detail", lang))
            featureRow("square.on.square", L.t("license_feature_layouts_title", lang), L.t("license_feature_layouts_detail", lang))
            featureRow("checkmark.seal.fill", L.t("license_feature_nowatermark_title", lang), L.t("license_feature_nowatermark_detail", lang))
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.hair, lineWidth: 1))
    }

    private func featureRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.honey)
                .frame(width: 30, height: 30)
                .background(Palette.honeySoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - The single offer

    @ViewBuilder
    private var offer: some View {
        if let product = store.pro {
            offerCard(price: product.displayPrice)
        } else if demoPrice != nil {
            offerCard(price: demoPrice!)
        } else if store.isLoading {
            ProgressView().tint(Palette.honey).frame(height: 70)
        } else {
            Text(L.t("pay_store_unavailable", lang))
                .font(.footnote)
                .foregroundStyle(Palette.sub)
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
        }
    }

    private func offerCard(price: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Palette.honey)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("pay_lifetime", lang))
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Palette.ink)
                Text(L.t("pay_lifetime_detail", lang))
                    .font(.caption)
                    .foregroundStyle(Palette.sub)
            }
            Spacer(minLength: 0)
            Text(price)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Palette.honey)
        }
        .padding(16)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.honey, lineWidth: 2))
    }

    // MARK: - CTA

    private var callToAction: some View {
        VStack(spacing: 12) {
            Button { buy() } label: {
                Text(L.t("pay_buy", lang))
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(LinearGradient.honey, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(busy || (store.pro == nil && demoPrice == nil))
            .opacity(store.pro == nil && demoPrice == nil ? 0.5 : 1)

            Button { restore() } label: {
                Text(L.t("restore_purchases", lang))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.honey)
            }
            .disabled(busy)

            if let err = store.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Palette.danger)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Legal + signature

    private var legal: some View {
        VStack(spacing: 10) {
            Text(L.t("pay_terms", lang))
                .font(.caption2)
                .foregroundStyle(Palette.faint)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link(L.t("privacy_policy", lang), destination: AppInfo.privacyPolicyURL)
                Link(L.t("support", lang), destination: AppInfo.supportURL)
            }
            .font(.caption2)
            .tint(Palette.sub)
        }
    }

    /// Crazy Bee Labs signature — deliberately last, below the app's own identity.
    private var signature: some View {
        Link(destination: AppInfo.siteURL) {
            VStack(spacing: 8) {
                Rectangle().fill(Palette.hair).frame(width: 120, height: 1)
                Image("CrazyBeeLabsLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 22)
                    .opacity(0.85)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// -demoPrices renders the real store price without StoreKit, so the App Review
    /// screenshot can be captured with `simctl` (which bypasses the scheme's StoreKit
    /// configuration). Debug builds only — never in a shipped binary.
    private var demoPrice: String? {
        #if DEBUG
        return CommandLine.arguments.contains("-demoPrices") ? "9,99 €" : nil
        #else
        return nil
        #endif
    }

    // MARK: - Actions

    private func buy() {
        guard let product = store.pro else { return }
        busy = true
        Task { await store.purchase(product); busy = false }
    }

    private func restore() {
        busy = true
        Task { await store.restore(); busy = false }
    }
}
