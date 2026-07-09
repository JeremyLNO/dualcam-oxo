import Foundation

/// A clean, user-facing error for every account/network call — never a raw
/// `URLError` or JSON blob reaching the UI.
enum APIError: LocalizedError {
    case offline
    case server(String)
    case unauthorized
    case decoding
    case unknown

    var errorDescription: String? {
        switch self {
        case .offline:      return L.t("err_offline")
        case .server(let m): return m
        case .unauthorized: return L.t("err_unauthorized")
        case .decoding:      return L.t("err_generic")
        case .unknown:       return L.t("err_generic")
        }
    }
}

/// Thin JSON client for the Crazy Bee Labs account API. Every call maps
/// failures to `APIError` so screens can show one clear message instead of
/// spinning forever or crashing on an unexpected payload.
enum APIClient {
    private struct ErrorBody: Decodable { let error: String? }
    private struct OKBody: Decodable { let ok: Bool }

    /// POST `path` with a JSON body, decoding a JSON response of type `R`.
    static func post<Body: Encodable, R: Decodable>(
        _ path: String, body: Body, token: String? = nil
    ) async throws -> R {
        try await send(path: path, method: "POST", body: body, token: token)
    }

    /// POST/DELETE with a JSON body, expecting only `{ ok: true }` back.
    @discardableResult
    static func post(_ path: String, body: some Encodable, token: String? = nil) async throws -> Bool {
        let res: OKBody = try await send(path: path, method: "POST", body: body, token: token)
        return res.ok
    }

    @discardableResult
    static func delete(_ path: String, body: some Encodable, token: String? = nil) async throws -> Bool {
        let res: OKBody = try await send(path: path, method: "DELETE", body: body, token: token)
        return res.ok
    }

    private static func send<Body: Encodable, R: Decodable>(
        path: String, method: String, body: Body, token: String?
    ) async throws -> R {
        guard await NetworkMonitor.shared.isOnline else { throw APIError.offline }

        var req = URLRequest(url: AppInfo.apiBaseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        req.httpBody = try? JSONEncoder().encode(body)
        req.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw mapTransportError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.unknown }

        if http.statusCode == 401 {
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw APIError.server(message ?? L.t("err_generic"))
        }

        guard let decoded = try? JSONDecoder().decode(R.self, from: data) else {
            throw APIError.decoding
        }
        return decoded
    }

    private static func mapTransportError(_ error: Error) -> APIError {
        let nsError = error as NSError
        let offlineCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
            NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff,
        ]
        if nsError.domain == NSURLErrorDomain, offlineCodes.contains(nsError.code) {
            return .offline
        }
        return .unknown
    }
}
