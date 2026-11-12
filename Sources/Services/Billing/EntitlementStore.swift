import Foundation
import Observation
import StoreKit

/// StoreKit 2 purchases for Free / Pro / Ultra. Syncs the active entitlement to the Loge account.
@MainActor
@Observable
public final class EntitlementStore {
    public private(set) var products: [Product] = []
    public private(set) var isLoading = false
    public private(set) var purchaseError: String?
    public private(set) var isPurchasing = false

    private let auth: AuthService

    public init(auth: AuthService = .shared) {
        self.auth = auth
        Task { await listenForTransactions() }
    }

    public func loadProducts() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: LogeProductID.allIDs)
            products = loaded.sorted { $0.id < $1.id }
        } catch {
            purchaseError = error.localizedDescription
            products = []
        }
    }

    public func product(for id: LogeProductID) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    @discardableResult
    public func purchase(_ product: Product) async -> Bool {
        guard auth.isAuthenticated else {
            purchaseError = "Connectez un compte foyer avant d’acheter."
            return false
        }
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                try await syncJWSToAccount(verification.jwsRepresentation, productID: transaction.productID)
                await transaction.finish()
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    public func restore() async {
        guard auth.isAuthenticated else {
            purchaseError = "Connectez un compte foyer avant de restaurer."
            return
        }
        purchaseError = nil
        do {
            try await AppStore.sync()
            var synced = false
            for await result in Transaction.currentEntitlements {
                let transaction = try checkVerified(result)
                try await syncJWSToAccount(result.jwsRepresentation, productID: transaction.productID)
                synced = true
            }
            if !synced {
                purchaseError = "Aucun abonnement à restaurer pour cet Apple ID."
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Private

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard let transaction = try? checkVerified(result) else { continue }
            if auth.isAuthenticated {
                try? await syncJWSToAccount(result.jwsRepresentation, productID: transaction.productID)
            }
            await transaction.finish()
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    private func syncJWSToAccount(_ jws: String, productID: String) async throws {
        guard LogeProductID.plan(forProductID: productID) != nil else { return }
        try await auth.reportApplePurchase(jwsRepresentation: jws)
    }
}
