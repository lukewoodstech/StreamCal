import SwiftUI
import RevenueCat
import RevenueCatUI

// MARK: - Paywall

/// Presents RevenueCat's built-in Paywall UI.
/// The paywall content and design are configured in the RevenueCat dashboard
/// under Paywalls. Falls back to the default RC paywall if none is configured.
struct AppPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchaseService: PurchaseService

    var body: some View {
        PaywallView(displayCloseButton: true)
            .onPurchaseCompleted { customerInfo in
                let isPro = customerInfo.entitlements["StreamCal Pro"]?.isActive == true
                if isPro { dismiss() }
            }
            .onRestoreCompleted { customerInfo in
                let isPro = customerInfo.entitlements["StreamCal Pro"]?.isActive == true
                if isPro { dismiss() }
            }
    }
}

// MARK: - Customer Center

/// RevenueCat's built-in subscription management and support UI.
/// Shows active subscriptions, allows cancellation help, and handles refund requests.
struct AppCustomerCenterView: View {
    var body: some View {
        CustomerCenterView()
    }
}

// MARK: - Paywall Sheet Modifier

/// Convenience modifier — present the paywall as a sheet.
extension View {
    func paywallSheet(isPresented: Binding<Bool>) -> some View {
        self.sheet(isPresented: isPresented) {
            AppPaywallView()
        }
    }
}
