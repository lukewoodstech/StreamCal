import SwiftUI
import Combine
import RevenueCat

// MARK: - Purchase Service

/// Single source of truth for subscription state.
/// Observes CustomerInfo in real time via `customerInfoStream`.
@MainActor
final class PurchaseService: ObservableObject {

    static let shared = PurchaseService()

    // MARK: - Published State

    // In DEBUG builds, always Pro so AI features are testable without a subscription.
    // Flip to `false` for release.
    #if DEBUG
    @Published private(set) var isPro: Bool = true
    #else
    @Published private(set) var isPro: Bool = false
    #endif
    @Published private(set) var customerInfo: CustomerInfo? = nil

    // MARK: - Configuration

    /// Call once in `StreamCalApp.init()`.
    func configure(apiKey: String) {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)

        // Start observing customer info updates in real time
        Task { await observeCustomerInfo() }
    }

    // MARK: - Real-time Observation

    private func observeCustomerInfo() async {
        for await info in Purchases.shared.customerInfoStream {
            customerInfo = info
            let entitledPro = info.entitlements["StreamCal Pro"]?.isActive == true
            #if !DEBUG
            isPro = entitledPro
            #else
            // In debug, only upgrade — never downgrade from the dev bypass
            if entitledPro { isPro = true }
            #endif
        }
    }

    // MARK: - Manual Refresh

    func refresh() async {
        guard let info = try? await Purchases.shared.customerInfo() else { return }
        customerInfo = info
        let entitledPro = info.entitlements["StreamCal Pro"]?.isActive == true
        #if !DEBUG
        isPro = entitledPro
        #else
        if entitledPro { isPro = true }
        #endif
    }

    // MARK: - Restore

    func restore() async throws {
        let info = try await Purchases.shared.restorePurchases()
        customerInfo = info
        isPro = info.entitlements["StreamCal Pro"]?.isActive == true
    }

    // MARK: - Customer ID (passed to AI backend)

    var customerID: String {
        Purchases.shared.appUserID
    }
}
