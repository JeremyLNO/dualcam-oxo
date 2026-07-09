import SwiftUI
import AuthenticationServices

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account = AccountManager.shared
    @ObservedObject private var network = NetworkMonitor.shared
    var lang: AppLanguage

    @State private var email = ""
    @State private var password = ""
    @State private var errorText: String?
    @State private var forgotSent = false
    @State private var showDeleteConfirm = false
    @State private var deleteConfirmText = ""
    @State private var deleting = false

    var body: some View {
        NavigationStack {
            Form {
                if !network.isOnline {
                    Section {
                        Label(L.t("err_offline", lang), systemImage: "wifi.slash")
                            .foregroundStyle(Palette.danger)
                    }
                }
                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(Palette.danger)
                    }
                }

                if let user = account.user {
                    signedInSection(user: user)
                } else {
                    signedOutSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(LinearGradient.appBackground.ignoresSafeArea())
            .navigationTitle(L.t("account_title", lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.t("done", lang)) { dismiss() }
                }
            }
        }
        .tint(Palette.honey)
        .preferredColorScheme(.dark)
    }

    // MARK: - Signed out

    private var signedOutSection: some View {
        Group {
            Section {
                Text(L.t("account_intro", lang))
                    .font(.subheadline).foregroundStyle(Palette.sub)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleAppleCompletion(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(account.isBusy)
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }

            Section(L.t("or_email", lang)) {
                TextField(L.t("email", lang), text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(L.t("password", lang), text: $password)
                    .textContentType(.password)

                Button {
                    signIn()
                } label: {
                    HStack {
                        Spacer()
                        Text(account.isBusy ? L.t("signing_in", lang) : L.t("sign_in", lang))
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(account.isBusy || email.isEmpty || password.isEmpty)

                Button(L.t("forgot_password", lang)) { requestReset() }
                    .font(.footnote)
                    .disabled(account.isBusy || email.isEmpty)

                if forgotSent {
                    Text(L.t("forgot_password_sent", lang))
                        .font(.footnote).foregroundStyle(Palette.sub)
                }
            }

            Section {
                Link(destination: AppInfo.signUpURL) {
                    Text(L.t("no_account_yet", lang))
                }
                .font(.footnote)
            }
        }
    }

    // MARK: - Signed in

    private func signedInSection(user: AccountManager.AccountUser) -> some View {
        Group {
            Section {
                HStack {
                    Text(L.t("signed_in_as", lang))
                    Spacer()
                    Text(user.email).foregroundStyle(Palette.sub)
                }
                Button(L.t("sign_out", lang), role: .destructive) { account.signOut() }
            }

            Section(L.t("danger_zone", lang)) {
                if !showDeleteConfirm {
                    Button(L.t("delete_account", lang), role: .destructive) {
                        showDeleteConfirm = true
                    }
                } else {
                    Text(L.t("delete_account_warning", lang))
                        .font(.footnote).foregroundStyle(Palette.sub)
                    TextField(L.t("delete_account_confirm_label", lang), text: $deleteConfirmText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button(role: .destructive) {
                        deleteAccount()
                    } label: {
                        HStack {
                            Spacer()
                            Text(deleting ? L.t("deleting", lang) : L.t("delete_account_button", lang))
                            Spacer()
                        }
                    }
                    .disabled(deleting || deleteConfirmText != "DELETE")
                    Button(L.t("cancel_generic", lang)) {
                        showDeleteConfirm = false
                        deleteConfirmText = ""
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        errorText = nil
        switch result {
        case .success(let authorization):
            Task {
                do {
                    try await account.completeAppleSignIn(authorization)
                } catch {
                    errorText = error.localizedDescription
                }
            }
        case .failure(let error):
            // The user dismissing the Apple sheet isn't an error worth surfacing.
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorText = error.localizedDescription
            }
        }
    }

    private func signIn() {
        errorText = nil
        Task {
            do {
                try await account.signIn(email: email, password: password)
                password = ""
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func requestReset() {
        errorText = nil
        Task {
            do {
                try await account.requestPasswordReset(email: email)
                withAnimation { forgotSent = true }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func deleteAccount() {
        errorText = nil
        deleting = true
        Task {
            do {
                try await account.deleteAccount()
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            deleting = false
        }
    }
}
