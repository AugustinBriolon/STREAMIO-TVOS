import SwiftUI

/// Shown while this Apple TV is not signed in to an account: offers to sign in (QR code or email, the
/// same sheet as Settings) or to carry on without an account. Comes back after the device is signed
/// out from the account's device list, and says so.
struct WelcomeView: View {
    @Environment(AuthService.self) private var auth
    @State private var isPairing = false
    @FocusState private var signInFocused: Bool

    private var title: String {
        auth.wasSignedOutRemotely ? "Cet appareil a été déconnecté" : "Bienvenue sur Loge"
    }

    private var message: String {
        auth.wasSignedOutRemotely
            ? "Il a été retiré de votre compte depuis un autre appareil. Vos profils et votre historique sont toujours là : reconnectez-vous pour les synchroniser à nouveau."
            : "Connectez-vous pour retrouver vos profils, votre liste et votre historique sur toutes vos Apple TV."
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.m) {
                Text(title)
                    .font(Theme.Typography.billboardTitle)
                    .tracking(Theme.Typography.displayTracking)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Theme.Layout.synopsisWidth)
            }
            HStack(spacing: Theme.Spacing.m) {
                Button("Se connecter", systemImage: "person.crop.circle") { isPairing = true }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .focused($signInFocused)
                Button("Continuer sans compte") { auth.dismissWelcome() }
                    .buttonStyle(PillButtonStyle())
            }
            .focusSection()
        }
        .padding(Theme.Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.canvas.ignoresSafeArea())
        .defaultFocus($signInFocused, true)
        .sheet(isPresented: $isPairing) { PairingModalSheet() }
    }
}
