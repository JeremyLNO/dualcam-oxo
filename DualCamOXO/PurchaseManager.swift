import StoreKit

/// Owns the "DualCam OxO Pro" entitlement: a single non-consumable unlock for
/// 4K quality + watermark-free combined exports. StoreKit 2 is the source of
/// truth (no backend involved) — `Transaction.currentEntitlements` is what
/// Restore Purchases re-derives from, so it works after a reinstall or on a
/// new device signed into the same Apple ID / Family Sharing group.
@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    @Published private(set) var isPro = false
    @Published private(set) var product: Product?
    @Published private(set) var isLoading = false

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { [weak self] in await self?.observeTransactionUpdates() }
        Task { [weak self] in
            await self?.loadProduct()
            await self?.refreshEntitlements()
        }
    }

    deinit { updatesTask?.cancel() }

    func loadProduct() async {
        guard product == nil, NetworkMonitor.shared.isOnline else { return }
        product = try? await Product.products(for: [AppInfo.proProductID]).first
    }

    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == AppInfo.proProductID {
                isPro = true
                return
            }
        }
        isPro = false
    }

    func purchase() async throws {
        guard NetworkMonitor.shared.isOnline else { throw APIError.offline }
        if product == nil { await loadProduct() }
        guard let product else { throw APIError.unknown }

        isLoading = true
        defer { isLoading = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await transaction.finish()
                isPro = true
            }
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    func restore() async throws {
        guard NetworkMonitor.shared.isOnline else { throw APIError.offline }
        isLoading = true
        defer { isLoading = false }
        try await AppStore.sync()
        await refreshEntitlements()
    }

    private func observeTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result,
                  transaction.productID == AppInfo.proProductID else { continue }
            isPro = true
            await transaction.finish()
        }
    }
}
