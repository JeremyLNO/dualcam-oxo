import Foundation
import AuthenticationServices

/// Owns the signed-in state for the whole app. The session token lives in the
/// Keychain; a small non-sensitive user cache lives in UserDefaults so the UI
/// has something to show before the first network round-trip.
@MainActor
final class AccountManager: NSObject, ObservableObject {
    static let shared = AccountManager()

    struct AccountUser: Codable, Equatable {
        let id: String
        let email: String
        let name: String?
    }

    @Published private(set) var user: AccountUser?
    @Published private(set) var isBusy = false

    private(set) var token: String?
    private static let cacheKey = "account.cachedUser"

    private override init() {
        super.init()
        token = Keychain.load()
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(AccountUser.self, from: data) {
            user = cached
        }
        // A cached user with no token is stale (e.g. a prior sign-out that failed
        // to clear the cache) — don't show a signed-in state that isn't backed by a session.
        if token == nil { user = nil }
    }

    var isSignedIn: Bool { token != nil }

    // MARK: - Sign in with Apple
    //
    // The native `SignInWithAppleButton` (AuthenticationServices, SwiftUI) drives the
    // system prompt itself — this just exchanges the resulting credential for a
    // session with our backend, which verifies the identity token against Apple's keys.

    func completeAppleSignIn(_ authorization: ASAuthorization) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw APIError.unknown
        }
        isBusy = true
        defer { isBusy = false }

        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }.joined(separator: " ")

        struct Req: Encodable { let identityToken: String; let name: String? }
        struct Res: Decodable { let token: String; let user: AccountUser }
        let res: Res = try await APIClient.post(
            "auth/mobile/apple",
            body: Req(identityToken: identityToken, name: name.isEmpty ? nil : name))
        setSession(token: res.token, user: res.user)
    }

    // MARK: - Email / password

    func signIn(email: String, password: String) async throws {
        isBusy = true
        defer { isBusy = false }
        struct Req: Encodable { let email: String; let password: String }
        struct Res: Decodable { let token: String; let user: AccountUser }
        let res: Res = try await APIClient.post(
            "auth/mobile/login", body: Req(email: email, password: password))
        setSession(token: res.token, user: res.user)
    }

    func requestPasswordReset(email: String) async throws {
        struct Req: Encodable { let email: String }
        try await APIClient.post("auth/forgot-password", body: Req(email: email))
    }

    // MARK: - Delete / sign out

    func deleteAccount() async throws {
        guard let token else { throw APIError.unauthorized }
        isBusy = true
        defer { isBusy = false }
        struct Req: Encodable { let confirm: String }
        try await APIClient.delete("account", body: Req(confirm: "DELETE"), token: token)
        signOut()
    }

    func signOut() {
        token = nil
        user = nil
        Keychain.clear()
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
    }

    private func setSession(token: String, user: AccountUser) {
        self.token = token
        self.user = user
        Keychain.save(token)
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }
}
