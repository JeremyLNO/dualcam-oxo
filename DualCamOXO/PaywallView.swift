import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var purchases = PurchaseManager.shared
    @ObservedObject private var network = NetworkMonitor.shared
    var lang: AppLanguage

    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(LinearGradient.honey)
                    .padding(.top, 8)

                Text(L.t("pro_title", lang))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)

                Text(L.t("pro_lead", lang))
                    .font(.subheadline)
                    .foregroundStyle(Palette.sub)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    featureRow(icon: "4k.tv.fill", text: L.t("pro_feature_4k", lang))
                    featureRow(icon: "seal.fill", text: L.t("pro_feature_watermark", lang))
                }
                .padding(.vertical, 6)

                if !network.isOnline {
                    Label(L.t("err_offline", lang), systemImage: "wifi.slash")
                        .font(.footnote).foregroundStyle(Palette.danger)
                } else if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Palette.danger)
                        .multilineTextAlignment(.center)
                }

                Button { buy() } label: {
                    HStack {
                        Spacer()
                        if purchases.isLoading {
                            ProgressView().tint(.black)
                        } else {
                            Text(buyLabel).font(.headline)
                        }
                        Spacer()
                    }
                    .foregroundStyle(.black)
                    .padding(.vertical, 14)
                    .background(LinearGradient.honey, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(purchases.isLoading || purchases.product == nil)

                Button(L.t("restore_purchases", lang)) { restore() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.sub)
                    .disabled(purchases.isLoading)
            }
            .padding(24)
            .background(LinearGradient.appBackground.ignoresSafeArea())
            .navigationTitle(L.t("dualcam_pro", lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.t("done", lang)) { dismiss() }
                }
            }
        }
        .tint(Palette.honey)
        .preferredColorScheme(.dark)
        .onChange(of: purchases.isPro) { _, pro in if pro { dismiss() } }
        .task { if purchases.product == nil { await purchases.loadProduct() } }
    }

    private var buyLabel: String {
        guard let price = purchases.product?.displayPrice else { return L.t("pro_unlock", lang) }
        return "\(L.t("pro_unlock", lang)) — \(price)"
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Palette.honey).frame(width: 26)
            Text(text).font(.subheadline).foregroundStyle(Palette.ink)
        }
    }

    private func buy() {
        errorText = nil
        Task {
            do { try await purchases.purchase() }
            catch { errorText = error.localizedDescription }
        }
    }

    private func restore() {
        errorText = nil
        Task {
            do {
                let wasPro = purchases.isPro
                try await purchases.restore()
                if !purchases.isPro && !wasPro { errorText = L.t("restore_none", lang) }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
