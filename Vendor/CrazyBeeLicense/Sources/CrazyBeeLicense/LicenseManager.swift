import Foundation
import Combine

/// Drop-in license/trial manager for Crazy Bee Labs macOS apps.
///
/// - 7-day free trial counted from the install date.
/// - A license key is validated against CrazyBeeLabs.com (the source of truth).
/// - Expiry is enforced locally via the cached `validUntil`; a *block* (non-payment)
///   takes effect the next time the server is reachable. Offline use keeps the last
///   known good state, so a network blip never disables the app.
///
/// Gate your app's functionality on `isFunctional`.
@MainActor
public final class LicenseManager: ObservableObject {

  public struct Config {
    public var apiBaseURL: URL
    public var bundleId: String
    public var purchaseURL: URL
    public var trialDays: Int
    public var checkInterval: TimeInterval

    /// - Parameters:
    ///   - apiBaseURL: e.g. `https://crazybeelabs.com`
    ///   - bundleId: this app's bundle identifier (binds the key to the app)
    ///   - purchaseURL: where "Buy a license" sends the user
    public init(
      apiBaseURL: URL,
      bundleId: String,
      purchaseURL: URL,
      trialDays: Int = 7,
      checkInterval: TimeInterval = 6 * 3600
    ) {
      self.apiBaseURL = apiBaseURL
      self.bundleId = bundleId
      self.purchaseURL = purchaseURL
      self.trialDays = trialDays
      self.checkInterval = checkInterval
    }
  }

  public enum State: Equatable {
    case trial(daysLeft: Int)
    case licensed(validUntil: Date?)   // nil == lifetime
    case expiredTrial
    case invalid(reason: String)       // "expired" / "blocked" / "revoked" / "not_found" / "wrong_app"
  }

  @Published public private(set) var state: State = .trial(daysLeft: 0)
  @Published public private(set) var licenseKey: String = ""
  @Published public private(set) var isChecking: Bool = false

  /// Whether the app should currently work (trial running, or a valid license).
  public var isFunctional: Bool {
    switch state {
    case .trial, .licensed: return true
    case .expiredTrial, .invalid: return false
    }
  }

  public var purchaseURL: URL { config.purchaseURL }

  private let config: Config
  private let defaults: UserDefaults
  private var timer: Timer?

  private var ns: String { "cbl.license.\(config.bundleId)." }
  private var kInstall: String { ns + "installDate" }
  private var kKey: String { ns + "key" }
  private var kStatus: String { ns + "status" }
  private var kValidUntil: String { ns + "validUntil" }
  private var kCheckedAt: String { ns + "checkedAt" }

  public init(config: Config, defaults: UserDefaults = .standard) {
    self.config = config
    self.defaults = defaults
    if defaults.object(forKey: kInstall) == nil {
      defaults.set(Date(), forKey: kInstall)
    }
    self.licenseKey = defaults.string(forKey: kKey) ?? ""
    recomputeState()
  }

  // MARK: - Trial

  private var installDate: Date { defaults.object(forKey: kInstall) as? Date ?? Date() }

  private var trialDaysLeft: Int {
    let elapsedDays = Int(Date().timeIntervalSince(installDate) / 86_400)
    return max(0, config.trialDays - elapsedDays)
  }

  // MARK: - Cached server truth

  private var cachedStatus: String? { defaults.string(forKey: kStatus) }
  private var cachedValidUntil: Date? { defaults.object(forKey: kValidUntil) as? Date }

  private func recomputeState() {
    let key = defaults.string(forKey: kKey) ?? ""
    if key.isEmpty {
      let left = trialDaysLeft
      state = left > 0 ? .trial(daysLeft: left) : .expiredTrial
      return
    }
    // Licence propriétaire (signée, hors-ligne) — prioritaire sur le serveur.
    if let v = OwnerLicense.verdict(for: key, bundleId: config.bundleId) {
      state = v.valid ? .licensed(validUntil: v.validUntil) : .invalid(reason: "invalid")
      return
    }
    if let status = cachedStatus {
      if status == "active" {
        if let until = cachedValidUntil, until <= Date() {
          state = .invalid(reason: "expired")
        } else {
          state = .licensed(validUntil: cachedValidUntil)
        }
      } else {
        state = .invalid(reason: status)
      }
    } else {
      // key entered but not validated yet → provisional access until the first check
      state = .licensed(validUntil: cachedValidUntil)
    }
  }

  // MARK: - Public API

  /// Stores and validates a license key. Returns true if it is currently valid.
  @discardableResult
  public func setLicenseKey(_ raw: String) async -> Bool {
    let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return false }
    defaults.set(key, forKey: kKey)
    defaults.removeObject(forKey: kStatus)
    defaults.removeObject(forKey: kValidUntil)
    licenseKey = key
    recomputeState()
    return await refresh()
  }

  public func removeLicenseKey() {
    [kKey, kStatus, kValidUntil, kCheckedAt].forEach { defaults.removeObject(forKey: $0) }
    licenseKey = ""
    recomputeState()
  }

  /// Re-validates against the server (no-op for trial with no key). Safe to call often.
  @discardableResult
  public func refresh() async -> Bool {
    let key = defaults.string(forKey: kKey) ?? ""
    guard !key.isEmpty else { recomputeState(); return false }

    // Licence propriétaire : tranchée hors-ligne, aucun appel serveur.
    if let v = OwnerLicense.verdict(for: key, bundleId: config.bundleId) {
      recomputeState()
      return v.valid
    }

    isChecking = true
    defer { isChecking = false }

    let result = await validateRemote(key: key)
    if result.networkError {
      recomputeState() // keep cached state; local expiry still enforced
      return isFunctional
    }

    let persistedStatus = result.status ?? result.reason ?? (result.valid ? "active" : "invalid")
    defaults.set(persistedStatus, forKey: kStatus)
    if let until = result.validUntil {
      defaults.set(until, forKey: kValidUntil)
    } else {
      defaults.removeObject(forKey: kValidUntil)
    }
    defaults.set(Date(), forKey: kCheckedAt)
    recomputeState()
    return result.valid
  }

  /// Validate now + on a timer. Also call `refresh()` when your app becomes active.
  public func startMonitoring() {
    Task { await refresh() }
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: config.checkInterval, repeats: true) { [weak self] _ in
      Task { await self?.refresh() }
    }
  }

  public func stopMonitoring() {
    timer?.invalidate()
    timer = nil
  }

  // MARK: - Network

  private struct ValidationResult {
    var valid: Bool
    var status: String?
    var validUntil: Date?
    var reason: String?
    var networkError: Bool
  }

  private func validateRemote(key: String) async -> ValidationResult {
    let url = config.apiBaseURL.appendingPathComponent("api/licenses/validate")
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.timeoutInterval = 15
    req.httpBody = try? JSONSerialization.data(
      withJSONObject: ["licenseKey": key, "bundleId": config.bundleId]
    )

    do {
      let (data, resp) = try await URLSession.shared.data(for: req)
      guard
        let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        return ValidationResult(valid: false, status: nil, validUntil: nil, reason: "server", networkError: true)
      }
      let valid = obj["valid"] as? Bool ?? false
      let status = obj["status"] as? String
      let reason = obj["reason"] as? String
      var until: Date?
      if let s = obj["validUntil"] as? String { until = Self.parseDate(s) }
      return ValidationResult(valid: valid, status: status, validUntil: until, reason: reason, networkError: false)
    } catch {
      return ValidationResult(valid: false, status: nil, validUntil: nil, reason: "offline", networkError: true)
    }
  }

  private static func parseDate(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
  }
}
