import SwiftUI

/// The 24h "are you happy?" card. Yes → App Store rating · No → support page.
struct ReviewPromptView: View {
    @ObservedObject var manager = ReviewManager.shared
    var lang: AppLanguage

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(LinearGradient.honey)
                .padding(.top, 8)

            Text(L.t("review_title", lang))
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)

            Text(L.t("review_body", lang))
                .font(.subheadline)
                .foregroundStyle(Palette.sub)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                Button { manager.handle(happy: true) } label: {
                    Text(L.t("review_yes", lang))
                        .font(.headline).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(LinearGradient.honey, in: RoundedRectangle(cornerRadius: 14))
                }
                Button { manager.handle(happy: false) } label: {
                    Text(L.t("review_no", lang))
                        .font(.headline).foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.top, 4)
        }
        .padding(24)
        .presentationBackground(Palette.bg1)
        .presentationDetents([.height(340)])
        .presentationCornerRadius(28)
        .interactiveDismissDisabled(false)
        .onDisappear { if manager.isPresented { manager.dismiss() } }
    }
}
