import StoreKit
import SwiftUI

/// Full-screen Free / Pro / Ultra comparison and purchase (tvOS couch UI).
struct SubscriptionPaywallView: View {
    @Environment(AuthService.self) private var auth
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(CloudSyncEngine.self) private var syncEngine
    @Environment(ProfileStore.self) private var profiles
    @Environment(AddonStore.self) private var addons
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var period: BillingPeriod = .monthly
    @State private var appeared = false
    @FocusState private var focus: PaywallFocus?

    private enum BillingPeriod: String, CaseIterable, Identifiable {
        case monthly, yearly
        var id: Self { self }
        var title: String {
            switch self {
            case .monthly: "Mensuel"
            case .yearly: "Annuel"
            }
        }
    }

    private enum PaywallFocus: Hashable {
        case close
        case period(BillingPeriod)
        case plan(LogePlan)
        case restore
        case lifetime
    }

    var body: some View {
        ZStack {
            background
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                periodPicker
                plansRow
                footer
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.vertical, Theme.Spacing.xl)
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : Theme.Motion.entranceOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusSection()
        .defaultFocus($focus, .plan(auth.plan))
        .onExitCommand { dismiss() }
        .task {
            if entitlements.products.isEmpty {
                await entitlements.loadProducts()
            }
            withAnimation(reduceMotion ? nil : Theme.Motion.fade) {
                appeared = true
            }
            if focus == nil {
                focus = .plan(auth.plan)
            }
        }
    }

    // MARK: - Pieces

    private var background: some View {
        ZStack {
            Theme.Palette.canvas
            RadialGradient(
                colors: [Theme.Palette.accent.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 900
            )
            RadialGradient(
                colors: [Color.white.opacity(0.06), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Choisissez votre Loge")
                    .font(Theme.Typography.pageTitle)
                    .tracking(Theme.Typography.displayTracking)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Une offre pour le foyer entier — profils, addons et sync suivent le compte, pas seulement cette Apple TV.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: 980, alignment: .leading)
            }
            Spacer(minLength: Theme.Spacing.l)
            Button("Fermer", systemImage: "xmark") { dismiss() }
                .buttonStyle(PillButtonStyle())
                .focused($focus, equals: .close)
        }
    }

    private var periodPicker: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(BillingPeriod.allCases) { option in
                Button(option.title) { period = option }
                    .buttonStyle(ChipButtonStyle(isSelected: period == option))
                    .focused($focus, equals: .period(option))
            }
            if period == .yearly {
                Text("Économisez vs mensuel")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.match)
                    .padding(.leading, Theme.Spacing.s)
                    .transition(.opacity)
            }
            Spacer()
            Text("Offre actuelle : \(planTitle(auth.plan))")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .animation(Theme.Motion.fade, value: period)
    }

    private var plansRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.l) {
            planCard(.free, product: nil, recommended: false)
            planCard(.pro, product: product(for: .pro), recommended: auth.plan == .free)
            planCard(.ultra, product: product(for: .ultra), recommended: auth.plan == .pro)
        }
    }

    private func planCard(_ plan: LogePlan, product: Product?, recommended: Bool) -> some View {
        let limits = PlanLimits.forPlan(plan)
        let isCurrent = auth.plan == plan
        let unavailablePaid = plan != .free && product == nil && !entitlements.isLoading
        return Button {
            Task { await select(plan: plan, product: product) }
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Text(planTitle(plan))
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Spacer()
                    if recommended {
                        Text("Recommandé")
                            .font(Theme.Typography.badge)
                            .foregroundStyle(.black)
                            .padding(.horizontal, Theme.Spacing.s)
                            .padding(.vertical, Theme.Spacing.xxs)
                            .background(Theme.Palette.match, in: Capsule())
                    } else if isCurrent {
                        Text("Actuel")
                            .font(Theme.Typography.badge)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .padding(.horizontal, Theme.Spacing.s)
                            .padding(.vertical, Theme.Spacing.xxs)
                            .background(Theme.Palette.surfaceRaised, in: Capsule())
                    }
                }

                Text(priceLabel(plan: plan, product: product))
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .monospacedDigit()

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    featureRow("\(limits.maxProfiles) profil\(limits.maxProfiles > 1 ? "s" : "")")
                    featureRow("\(limits.maxAddons) extension\(limits.maxAddons > 1 ? "s" : "") installable\(limits.maxAddons > 1 ? "s" : "") (+ inclus Loge)")
                    featureRow("\(limits.maxTVSessions) Apple TV · \(limits.maxBrowserSessions) navigateur")
                    featureRow(limits.cloudSync ? "Sync cloud foyer" : "Données locales uniquement")
                    featureRow(limits.canRenameDevices ? "Renommer les appareils" : "Noms appareils fixes")
                }

                Spacer(minLength: Theme.Spacing.m)

                Text(ctaTitle(plan: plan, isCurrent: isCurrent, unavailable: unavailablePaid))
                    .font(Theme.Typography.button)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.s)
                    .foregroundStyle(isCurrent || plan == .free ? Theme.Palette.textSecondary : .black)
                    .background(
                        isCurrent || plan == .free ? Theme.Palette.surfaceRaised : Color.white,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    )

                if plan == .ultra, let lifetime = entitlements.product(for: .ultraLifetime), auth.plan != .ultra {
                    Text("ou \(lifetime.displayPrice) à vie")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, minHeight: 480, alignment: .topLeading)
            .background {
                PlanCardChrome(emphasized: recommended || plan == .ultra)
            }
        }
        .buttonStyle(PlanCardButtonStyle())
        .focused($focus, equals: .plan(plan))
        .disabled(unavailablePaid || entitlements.isPurchasing)
        .opacity(unavailablePaid ? 0.55 : 1)
    }

    private func featureRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.Palette.match)
            Text(text)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button("Restaurer les achats", systemImage: "arrow.clockwise") {
                Task {
                    await entitlements.restore()
                    applyPlanLocally()
                    await syncEngine.sync()
                }
            }
            .buttonStyle(PillButtonStyle())
            .focused($focus, equals: .restore)
            .disabled(entitlements.isPurchasing)

            if let lifetime = entitlements.product(for: .ultraLifetime), auth.plan != .ultra {
                Button("Ultra à vie — \(lifetime.displayPrice)") {
                    Task {
                        if await entitlements.purchase(lifetime) {
                            applyPlanLocally()
                            await syncEngine.sync()
                            dismiss()
                        }
                    }
                }
                .buttonStyle(PillButtonStyle(kind: .secondary))
                .focused($focus, equals: .lifetime)
                .disabled(entitlements.isPurchasing)
            }

            if entitlements.isLoading || entitlements.isPurchasing {
                ProgressView()
            }

            if let err = entitlements.purchaseError {
                Text(err)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.accent)
                    .lineLimit(2)
            }

            Spacer()

            Text("L’abonnement est géré par Apple. Annulation dans Réglages → Compte.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(maxWidth: 520, alignment: .trailing)
        }
    }

    // MARK: - Data

    private func product(for plan: LogePlan) -> Product? {
        let id: LogeProductID? = switch (plan, period) {
        case (.pro, .monthly): .proMonthly
        case (.pro, .yearly): .proYearly
        case (.ultra, .monthly): .ultraMonthly
        case (.ultra, .yearly): .ultraYearly
        default: nil
        }
        guard let id else { return nil }
        return entitlements.product(for: id)
    }

    private func priceLabel(plan: LogePlan, product: Product?) -> String {
        switch plan {
        case .free:
            return "Gratuit"
        case .pro, .ultra:
            if let product {
                return period == .yearly
                    ? "\(product.displayPrice) / an"
                    : "\(product.displayPrice) / mois"
            }
            return "—"
        }
    }

    private func planTitle(_ plan: LogePlan) -> String {
        switch plan {
        case .free: "Free"
        case .pro: "Pro"
        case .ultra: "Ultra"
        }
    }

    private func ctaTitle(plan: LogePlan, isCurrent: Bool, unavailable: Bool) -> String {
        if isCurrent { return "Offre active" }
        if unavailable { return "Bientôt" }
        switch plan {
        case .free: return "Continuer en Free"
        case .pro, .ultra: return "Choisir \(planTitle(plan))"
        }
    }

    private func select(plan: LogePlan, product: Product?) async {
        // Free and the active plan are browsable/confirmable — close the sheet.
        if plan == .free || plan == auth.plan {
            dismiss()
            return
        }
        guard let product else { return }
        if await entitlements.purchase(product) {
            applyPlanLocally()
            await syncEngine.sync()
            dismiss()
        }
    }

    private func applyPlanLocally() {
        profiles.plan = auth.plan
        addons.plan = auth.plan
    }
}

/// Focus + press scale only — no white sheen overlay on the card.
private struct PlanCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlanCardButtonBody(configuration: configuration)
    }
}

private struct PlanCardButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(
                Theme.Motion.scale(
                    focused: isFocused,
                    pressed: configuration.isPressed,
                    focusScale: 1.04,
                    reduceMotion: reduceMotion
                )
            )
            .animation(Theme.Motion.focus, value: isFocused)
            .animation(Theme.Motion.press, value: configuration.isPressed)
            .zIndex(isFocused ? 1 : 0)
    }
}

private struct PlanCardChrome: View {
    let emphasized: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
            .fill(Theme.Palette.surface.opacity(0.78))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? Theme.Palette.accent.opacity(0.85)
                            : Color.white.opacity(emphasized ? 0.18 : 0.08),
                        lineWidth: isFocused ? 2 : 1
                    )
            }
            .shadow(
                color: .black.opacity(isFocused ? 0.4 : 0.2),
                radius: isFocused ? 18 : 12,
                y: isFocused ? 10 : 6
            )
    }
}
