import SwiftUI

// MARK: - Billing View

/// Subscription management, credit purchases, and usage analytics.
/// Stripe Checkout opens in the default browser; all payment processing happens server-side.
struct BillingView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var currentTier: String = "free"
    @State private var creditsBalance: Int = 0
    @State private var creditsPerMonth: Int = 500
    @State private var subscriptionStatus: String?
    @State private var subscriptionPeriodEnd: Date?
    @State private var usageThisMonth: Int = 0
    @State private var requestsThisMonth: Int = 0
    @State private var byModel: [ModelUsage] = []
    @State private var recentPurchases: [CreditPurchase] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    struct ModelUsage: Identifiable {
        let id = UUID()
        let model: String
        let requests: Int
        let credits: Int
    }

    struct CreditPurchase: Identifiable {
        let id = UUID()
        let packKey: String
        let creditsAdded: Int
        let amountCents: Int
        let date: Date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            currentPlanCard
            usageCard
            upgradeTiersCard
            creditPacksCard
            if !recentPurchases.isEmpty {
                purchaseHistoryCard
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .alert("Billing Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Retry") { Task { await loadBillingData() } }
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .task { await loadBillingData() }
    }

    // MARK: - Current Plan

    private var currentPlanCard: some View {
        billingCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionHeader("Current Plan", icon: "crown.fill")

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(tierDisplayName)
                            .font(Typography.heading2)
                            .foregroundColor(.textPrimary)

                        if let status = subscriptionStatus, status != "active" {
                            Text(status.capitalized)
                                .font(Typography.captionSemibold)
                                .foregroundColor(status == "past_due" ? .orange : .textSecondary)
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, Spacing.xs)
                                .background(status == "past_due" ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.1))
                                .clipShape(Capsule())
                        }

                        if let end = subscriptionPeriodEnd {
                            Text("Renews \(end, style: .date)")
                                .font(Typography.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("\(creditsBalance)")
                            .font(Typography.displayMedium)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                        Text("credits remaining")
                            .font(Typography.caption)
                            .foregroundColor(.textSecondary)
                    }
                }

                // Usage bar
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text("\(usageThisMonth) / \(creditsPerMonth) credits this month")
                            .font(Typography.bodySmall)
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text("\(usagePercent)%")
                            .font(Typography.captionSemibold)
                            .foregroundColor(usagePercent > 80 ? .orange : .textSecondary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: Radius.sm)
                                .fill(usageBarColor)
                                .frame(width: geo.size.width * usageFraction, height: 6)
                        }
                    }
                    .frame(height: 6)
                }

                if currentTier != "free" {
                    Button("Manage Subscription") {
                        openPortal()
                    }
                    .font(Typography.bodySmall)
                    .foregroundColor(themeManager.palette.effectiveAccent)
                    .accessibilityLabel("Manage subscription in Stripe")
                }
            }
        }
    }

    // MARK: - Usage Breakdown

    private var usageCard: some View {
        billingCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionHeader("Usage This Month", icon: "chart.bar.fill")

                HStack(spacing: Spacing.massive) {
                    usageStat(value: "\(requestsThisMonth)", label: "Requests")
                    usageStat(value: "\(usageThisMonth)", label: "Credits Used")
                }

                if !byModel.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        Text("By Model")
                            .font(Typography.captionSemibold)
                            .foregroundColor(.textSecondary)

                        ForEach(byModel) { usage in
                            HStack {
                                Text(shortModelName(usage.model))
                                    .font(Typography.bodySmall)
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(usage.requests) req")
                                    .font(Typography.caption)
                                    .foregroundColor(.textSecondary)
                                Text("\(usage.credits) cr")
                                    .font(Typography.captionSemibold)
                                    .foregroundColor(.textPrimary)
                                    .frame(width: 60, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Upgrade Tiers

    private var upgradeTiersCard: some View {
        billingCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionHeader("Plans", icon: "arrow.up.circle.fill")

                VStack(spacing: Spacing.lg) {
                    tierRow(
                        name: "Free",
                        price: "$0",
                        credits: "500",
                        features: ["Free tier models"],
                        isCurrent: currentTier == "free",
                        priceKey: nil
                    )

                    Divider()

                    tierRow(
                        name: "Starter",
                        price: "$9.99/mo",
                        credits: "2,000",
                        features: ["Free + Fast models", "7-day free trial"],
                        isCurrent: currentTier == "starter",
                        priceKey: "starter_monthly"
                    )

                    Divider()

                    tierRow(
                        name: "Pro",
                        price: "$19.99/mo",
                        credits: "5,000",
                        features: ["All models", "14-day free trial"],
                        isCurrent: currentTier == "pro",
                        priceKey: "pro_monthly"
                    )

                    Divider()

                    tierRow(
                        name: "Team",
                        price: "$49.99/mo",
                        credits: "25,000",
                        features: ["All models + priority routing"],
                        isCurrent: currentTier == "team",
                        priceKey: "team_monthly"
                    )
                }
            }
        }
    }

    // MARK: - Credit Packs

    private var creditPacksCard: some View {
        billingCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionHeader("Credit Packs", icon: "plus.circle.fill")

                HStack(spacing: Spacing.lg) {
                    creditPackButton(credits: "1,000", price: "$4.99", packKey: "credits_1000")
                    creditPackButton(credits: "5,000", price: "$19.99", packKey: "credits_5000")
                    creditPackButton(credits: "20,000", price: "$69.99", packKey: "credits_20000")
                }
            }
        }
    }

    // MARK: - Purchase History

    private var purchaseHistoryCard: some View {
        billingCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionHeader("Recent Purchases", icon: "clock.fill")

                ForEach(recentPurchases) { purchase in
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("+\(purchase.creditsAdded) credits")
                                .font(Typography.bodySmall)
                                .foregroundColor(.textPrimary)
                            Text(purchase.date, style: .date)
                                .font(Typography.caption)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Text(formatCents(purchase.amountCents))
                            .font(Typography.bodySemibold)
                            .foregroundColor(.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: - Components

    private func tierRow(name: String, price: String, credits: String, features: [String], isCurrent: Bool, priceKey: String?) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.md) {
                    Text(name)
                        .font(Typography.heading3)
                        .foregroundColor(.textPrimary)

                    if isCurrent {
                        Text("Current")
                            .font(Typography.micro)
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.xxs)
                            .background(themeManager.palette.effectiveAccent)
                            .clipShape(Capsule())
                    }
                }

                Text("\(credits) credits/month")
                    .font(Typography.bodySmall)
                    .foregroundColor(.textSecondary)

                ForEach(features, id: \.self) { feature in
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "checkmark")
                            .font(Typography.micro)
                            .foregroundColor(.accentGreen)
                        Text(feature)
                            .font(Typography.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.sm) {
                Text(price)
                    .font(Typography.bodySemibold)
                    .foregroundColor(.textPrimary)

                if !isCurrent, let key = priceKey {
                    Button("Upgrade") {
                        openCheckout(priceKey: key)
                    }
                    .font(Typography.captionSemibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.vertical, Spacing.md)
                    .background(themeManager.palette.effectiveAccent)
                    .clipShape(Capsule())
                    .accessibilityLabel("Upgrade to \(name) plan")
                }
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    private func creditPackButton(credits: String, price: String, packKey: String) -> some View {
        Button {
            openCheckout(priceKey: packKey)
        } label: {
            VStack(spacing: Spacing.md) {
                Text(credits)
                    .font(Typography.heading3)
                    .foregroundColor(themeManager.palette.effectiveAccent)
                Text("credits")
                    .font(Typography.caption)
                    .foregroundColor(.textSecondary)
                Text(price)
                    .font(Typography.bodySemibold)
                    .foregroundColor(.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xxl)
            .background(themeManager.palette.bgCard.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Purchase \(credits) credits for \(price)")
    }

    private func usageStat(value: String, label: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(Typography.heading2)
                .foregroundColor(.textPrimary)
            Text(label)
                .font(Typography.caption)
                .foregroundColor(.textSecondary)
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(Typography.captionSemibold)
                .foregroundColor(themeManager.palette.effectiveAccent)
            Text(title)
                .font(Typography.captionSemibold)
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
                .tracking(0.4)
        }
    }

    @ViewBuilder
    private func billingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(Spacing.huge)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)
            .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
    }

    // MARK: - Computed

    private var tierDisplayName: String {
        switch currentTier {
        case "starter": return "Starter"
        case "pro": return "Pro"
        case "team": return "Team"
        default: return "Free"
        }
    }

    private var usagePercent: Int {
        guard creditsPerMonth > 0 else { return 0 }
        return min(100, (usageThisMonth * 100) / creditsPerMonth)
    }

    private var usageFraction: CGFloat {
        guard creditsPerMonth > 0 else { return 0 }
        return min(1.0, CGFloat(usageThisMonth) / CGFloat(creditsPerMonth))
    }

    private var usageBarColor: Color {
        if usagePercent > 90 { return .red }
        if usagePercent > 70 { return .orange }
        return themeManager.palette.effectiveAccent
    }

    private func shortModelName(_ model: String) -> String {
        // Trim provider prefixes for display
        if let slash = model.lastIndex(of: "/") {
            return String(model[model.index(after: slash)...])
        }
        return model
    }

    private func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }

    // MARK: - Actions

    private func openCheckout(priceKey: String) {
        guard let url = URL(string: "\(PlatformService.baseURL)/api/billing/checkout") else { return }

        // Fire-and-forget: POST to backend, get Stripe Checkout URL, open in browser
        Task {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = PlatformService.authToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let body: [String: String] = ["priceKey": priceKey]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let checkoutURL = json["url"] as? String,
                      let stripeURL = URL(string: checkoutURL) else {
                    await MainActor.run { errorMessage = "Could not start checkout. Please try again." }
                    return
                }
                #if os(macOS)
                NSWorkspace.shared.open(stripeURL)
                #else
                await UIApplication.shared.open(stripeURL)
                #endif
            } catch {
                await MainActor.run { errorMessage = "Checkout failed: \(error.localizedDescription)" }
            }
        }
    }

    private func openPortal() {
        guard let url = URL(string: "\(PlatformService.baseURL)/api/billing/portal") else { return }

        Task {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = PlatformService.authToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: [:] as [String: String])

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let portalURL = json["url"] as? String,
                      let stripeURL = URL(string: portalURL) else {
                    await MainActor.run { errorMessage = "Could not open subscription portal. Please try again." }
                    return
                }
                #if os(macOS)
                NSWorkspace.shared.open(stripeURL)
                #else
                await UIApplication.shared.open(stripeURL)
                #endif
            } catch {
                await MainActor.run { errorMessage = "Portal request failed: \(error.localizedDescription)" }
            }
        }
    }

    // MARK: - Data Loading

    private func loadBillingData() async {
        guard let url = URL(string: "\(PlatformService.baseURL)/api/billing/usage") else { return }

        isLoading = true
        defer { isLoading = false }

        var request = URLRequest(url: url)
        if let token = PlatformService.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        do {
            let (responseData, _) = try await URLSession.shared.data(for: request)
            data = responseData
        } catch {
            errorMessage = "Could not load billing data: \(error.localizedDescription)"
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            errorMessage = "Invalid response from billing server."
            return
        }

        await MainActor.run {
            currentTier = json["tier"] as? String ?? "free"
            creditsBalance = json["creditsBalance"] as? Int ?? 0
            creditsPerMonth = json["creditsPerMonth"] as? Int ?? 500
            subscriptionStatus = json["subscriptionStatus"] as? String
            usageThisMonth = json["creditsUsedThisMonth"] as? Int ?? 0
            requestsThisMonth = json["requestsThisMonth"] as? Int ?? 0

            if let periodEnd = json["subscriptionPeriodEnd"] as? Int, periodEnd > 0 {
                subscriptionPeriodEnd = Date(timeIntervalSince1970: TimeInterval(periodEnd) / 1000.0)
            }

            if let models = json["byModel"] as? [[String: Any]] {
                byModel = models.compactMap { m in
                    guard let model = m["model"] as? String else { return nil }
                    return ModelUsage(
                        model: model,
                        requests: m["requests"] as? Int ?? 0,
                        credits: m["credits"] as? Int ?? 0
                    )
                }
            }

            if let purchases = json["recentPurchases"] as? [[String: Any]] {
                recentPurchases = purchases.compactMap { p in
                    guard let packKey = p["pack_key"] as? String else { return nil }
                    let createdAt = p["created_at"] as? Int ?? 0
                    return CreditPurchase(
                        packKey: packKey,
                        creditsAdded: p["credits_added"] as? Int ?? 0,
                        amountCents: p["amount_cents"] as? Int ?? 0,
                        date: Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000.0)
                    )
                }
            }
        }
    }
}
