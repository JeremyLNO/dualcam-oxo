import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var notifs = NotificationService.shared
    @ObservedObject private var account = AccountManager.shared
    @ObservedObject private var purchases = PurchaseManager.shared
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.systemDefault.rawValue

    @State private var updateStatus: String?
    @State private var checking = false
    @State private var showAccount = false
    @State private var showPaywall = false
    @State private var restoreStatus: String?
    @State private var restoring = false

    private var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .en }

    var body: some View {
        NavigationStack {
            Form {
                // Capture
                Section(L.t("capture_section", lang)) {
                    Picker(L.t("set_default_quality", lang), selection: qualityBinding) {
                        ForEach(VideoQuality.allCases) { q in
                            if q == .uhd4k && !purchases.isPro {
                                Label(L.t(q.titleKey, lang), systemImage: "lock.fill").tag(q)
                            } else {
                                Text(L.t(q.titleKey, lang)).tag(q)
                            }
                        }
                    }
                    Toggle(L.t("set_grid", lang), isOn: $settings.showGrid)
                    Toggle(L.t("flash", lang), isOn: $settings.flashDefault)
                }

                // Pro
                Section(L.t("dualcam_pro", lang)) {
                    if purchases.isPro {
                        Label(L.t("pro_row_active", lang), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Palette.honey)
                    } else {
                        Button { showPaywall = true } label: {
                            Label(L.t("pro_row_title", lang), systemImage: "sparkles")
                        }
                        .foregroundStyle(Palette.ink)
                    }
                    Button {
                        restorePurchases()
                    } label: {
                        HStack {
                            Text(L.t("restore_purchases", lang))
                            Spacer()
                            if restoring { ProgressView() }
                            else if let restoreStatus { Text(restoreStatus).foregroundStyle(Palette.sub).font(.footnote) }
                        }
                    }
                    .foregroundStyle(Palette.ink)
                    .disabled(restoring)
                }

                // Save to Photos
                Section(L.t("save_mode", lang)) {
                    Picker(L.t("save_mode", lang), selection: $settings.saveMode) {
                        ForEach(SaveMode.allCases) { m in
                            Label(L.t(m.titleKey, lang), systemImage: m.icon).tag(m)
                        }
                    }
                    .pickerStyle(.inline).labelsHidden()
                    Text(L.t(settings.saveMode.descKey, lang))
                        .font(.footnote).foregroundStyle(Palette.sub)

                    if settings.saveMode == .combined {
                        Picker(L.t("combined_layout", lang), selection: $settings.combinedLayout) {
                            ForEach(CombinedLayout.allCases) { l in
                                Label(L.t(l.titleKey, lang), systemImage: l.icon).tag(l)
                            }
                        }
                    }
                }

                // Language
                Section(L.t("general", lang)) {
                    Picker(L.t("set_language", lang), selection: $languageRaw) {
                        ForEach(AppLanguage.allCases) { l in
                            Text("\(l.flag)  \(l.name)").tag(l.rawValue)
                        }
                    }
                }

                // Notifications
                Section {
                    Toggle(L.t("set_notifications", lang), isOn: Binding(
                        get: { settings.notificationsEnabled && notifs.authorized },
                        set: { on in
                            settings.notificationsEnabled = on
                            if on { Task { await notifs.requestAuthorization() } }
                        }))
                    Button {
                        Task { await runUpdateCheck() }
                    } label: {
                        HStack {
                            Label(L.t("check_updates", lang), systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if checking { ProgressView() }
                            else if let updateStatus { Text(updateStatus).foregroundStyle(Palette.sub) }
                        }
                    }
                } header: {
                    Text(L.t("notif_section", lang))
                } footer: {
                    Text(L.t("set_notifications_desc", lang))
                }

                // Account
                Section(L.t("account_section", lang)) {
                    Button { showAccount = true } label: {
                        HStack {
                            Label(L.t("account_manage", lang), systemImage: "person.crop.circle")
                            Spacer()
                            Text(account.user?.email ?? L.t("account_not_signed_in", lang))
                                .font(.footnote).foregroundStyle(Palette.sub)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(Palette.ink)
                }

                // About
                Section(L.t("about", lang)) {
                    Link(destination: AppInfo.supportURL) {
                        Label(L.t("support", lang), systemImage: "lightbulb")
                    }
                    Link(destination: AppInfo.privacyPolicyURL) {
                        Label(L.t("privacy_policy", lang), systemImage: "hand.raised")
                    }
                    Link(destination: AppInfo.appStoreReviewURL) {
                        Label(L.t("rate_app", lang), systemImage: "star")
                    }
                    HStack {
                        Text(L.t("version", lang)); Spacer()
                        Text(AppInfo.versionString).foregroundStyle(Palette.sub)
                    }
                }

                // Signature
                Section {
                    Link(destination: AppInfo.siteURL) {
                        VStack(spacing: 8) {
                            Image("CrazyBeeLabsLogo")
                                .resizable().scaledToFit().frame(height: 30)
                            Text("crazybeelabs.com")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Palette.honey)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LinearGradient.appBackground.ignoresSafeArea())
            .navigationTitle(L.t("settings", lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.t("done", lang)) { dismiss() }
                }
            }
        }
        .tint(Palette.honey)
        .preferredColorScheme(.dark)
        .onAppear {
            notifs.refreshAuthorization()
            // Dev screenshot hooks, mirroring -openSettings.
            if CommandLine.arguments.contains("-openAccount") { showAccount = true }
            if CommandLine.arguments.contains("-openPaywall") { showPaywall = true }
        }
        .sheet(isPresented: $showAccount) { AccountView(lang: lang) }
        .sheet(isPresented: $showPaywall) { PaywallView(lang: lang) }
    }

    /// Selecting 4K without Pro opens the paywall instead of applying the setting.
    private var qualityBinding: Binding<VideoQuality> {
        Binding(
            get: { settings.quality },
            set: { newValue in
                if newValue == .uhd4k && !purchases.isPro {
                    showPaywall = true
                } else {
                    settings.quality = newValue
                }
            })
    }

    private func runUpdateCheck() async {
        checking = true
        let newer = await notifs.checkForUpdate()
        checking = false
        updateStatus = newer.map { "\(L.t("update_available", lang)) · \($0)" } ?? L.t("up_to_date", lang)
    }

    private func restorePurchases() {
        restoring = true
        restoreStatus = nil
        Task {
            do {
                let wasPro = purchases.isPro
                try await purchases.restore()
                restoreStatus = (purchases.isPro || wasPro) ? L.t("restore_done", lang) : L.t("restore_none", lang)
            } catch {
                restoreStatus = error.localizedDescription
            }
            restoring = false
        }
    }
}
