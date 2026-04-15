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

// MARK: - Pro Management Sheet

struct ProManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchaseService: PurchaseService

    @State private var showingCustomerCenter = false

    private static let proFeatures: [(icon: String, label: String, detail: String)] = [
        ("sparkles",        "Ask StreamCal AI",      "Natural language answers about your library"),
        ("rectangle.stack", "Discovery Cards",        "Tap AI recommendations to instantly add shows"),
        ("bell.badge",      "Smart Notifications",    "Weekly previews and personalized daily briefs"),
    ]

    private var entitlement: EntitlementInfo? {
        purchaseService.customerInfo?.entitlements["StreamCal Pro"]
    }

    private var renewalDate: String? {
        guard let date = entitlement?.expirationDate else { return nil }
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }

    private var willRenew: Bool {
        entitlement?.willRenew ?? false
    }

    private var periodLabel: String {
        switch entitlement?.periodType {
        case .trial:  return "Free Trial"
        case .intro:  return "Introductory Offer"
        default:      return "StreamCal Pro"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // Hero
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(DS.Color.ai.opacity(0.15))
                                .frame(width: 72, height: 72)
                            Image(systemName: "sparkles")
                                .font(.system(size: 30))
                                .foregroundStyle(DS.Color.ai)
                        }
                        Text(periodLabel)
                            .font(.title2)
                            .fontWeight(.bold)
                        if let date = renewalDate {
                            Text(willRenew ? "Renews \(date)" : "Access until \(date)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)

                    // Features
                    VStack(alignment: .leading, spacing: 0) {
                        Text("What's included")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.4)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(Self.proFeatures, id: \.label) { feature in
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(DS.Color.ai.opacity(0.12))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: feature.icon)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(DS.Color.ai)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(feature.label)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(feature.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                if feature.label != Self.proFeatures.last?.label {
                                    Divider().padding(.leading, 66)
                                }
                            }
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 16)
                    }

                    // Downgrade info
                    if willRenew {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("If you cancel")
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.4)
                                .padding(.horizontal, 16)

                            VStack(alignment: .leading, spacing: 6) {
                                Label("AI chat and discovery cards will stop working", systemImage: "xmark.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Label("Your library, calendar, and notifications stay intact", systemImage: "checkmark.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Label("You keep access until the end of your billing period", systemImage: "checkmark.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(16)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 16)
                        }
                    }

                    // Actions
                    VStack(spacing: 12) {
                        if entitlement != nil {
                            Button {
                                showingCustomerCenter = true
                            } label: {
                                HStack {
                                    Text(willRenew ? "Cancel Subscription" : "Manage Subscription")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .imageScale(.small)
                                        .fontWeight(.semibold)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(willRenew ? Color.red.opacity(0.1) : Color.secondary.opacity(0.1),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(willRenew ? .red : .primary)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }

                        Button("Done") { dismiss() }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCustomerCenter) {
                AppCustomerCenterView()
            }
        }
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
