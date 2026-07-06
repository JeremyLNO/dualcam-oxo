import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var notifs = NotificationService.shared
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.systemDefault.rawValue

    @State private var updateStatus: String?
    @State private var checking = false

    private var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .en }

    var body: some View {
        NavigationStack {
            Form {
                // Capture
                Section(L.t("capture_section", lang)) {
                    Picker(L.t("set_default_quality", lang), selection: $settings.quality) {
                        ForEach(VideoQuality.allCases) { q in
                            Text(L.t(q.titleKey, lang)).tag(q)
                        }
                    }
                    Toggle(L.t("set_grid", lang), isOn: $settings.showGrid)
                    Toggle(L.t("flash", lang), isOn: $settings.flashDefault)
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
                    Link(destination: AppInfo.signUpURL) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(L.t("create_account", lang), systemImage: "person.crop.circle.badge.plus")
                            Text(L.t("create_account_desc", lang))
                                .font(.footnote).foregroundStyle(Palette.sub)
                        }
                    }
                }

                // About
                Section(L.t("about", lang)) {
                    Link(destination: AppInfo.supportURL) {
                        Label(L.t("support", lang), systemImage: "lightbulb")
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
        .onAppear { notifs.refreshAuthorization() }
    }

    private func runUpdateCheck() async {
        checking = true
        let newer = await notifs.checkForUpdate()
        checking = false
        updateStatus = newer.map { "\(L.t("update_available", lang)) · \($0)" } ?? L.t("up_to_date", lang)
    }
}
