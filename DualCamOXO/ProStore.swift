import StoreKit
import SwiftUI

/// StoreKit 2 entitlement manager for DualCam OxO Pro.
///
/// iOS unlocks are **In-App Purchases only** — App Review guideline 3.1.1 forbids
/// unlocking paid features with a licence bought outside the App Store (that's what
/// the macOS apps do with the shared `CrazyBeeLicense` package). Here the package
/// only runs the free trial; the purchase itself goes through StoreKit.
@MainActor
final class ProStore: ObservableObject {
    static let shared = ProStore()

    /// Non-consumable one-off unlock.
    static let proID = "company.lno.dualcamoxo.pro"
    static var productIDs: [String] { [proID] }

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro = false
    @Published private(set) var isLoading = true
    @Published var lastError: String?

    var pro: Product? { products.first { $0.id == Self.proID } }
    /// True when StoreKit returned nothing (product not configured yet / offline).
    var hasNoProducts: Bool { products.isEmpty }

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = listenForTransactions()
        Task { await load(); await refreshEntitlement() }
    }

    deinit { updatesTask?.cancel() }

    func load() async {
        isLoading = true
        products = (try? await Product.products(for: Self.productIDs)) ?? []
        isLoading = false
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        lastError = nil
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                    return isPro
                }
                lastError = L.t("pay_error_unverified")
                return false
            case .userCancelled:
                return false
            case .pending:
                lastError = L.t("pay_pending")
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Backs the required "Restore Purchases" button.
    func restore() async {
        lastError = nil
        do { try await AppStore.sync() } catch { /* cancelled or offline — entitlements below still apply */ }
        await refreshEntitlement()
        if !isPro { lastError = L.t("pay_nothing_to_restore") }
    }

    func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }
            guard Self.productIDs.contains(t.productID), t.revocationDate == nil else { continue }
            active = true
        }
        isPro = active
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
    }
}
