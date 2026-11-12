import SwiftUI
import CoreImage

/// Modal de connexion et de jumelage pour synchroniser l'Apple TV avec le foyer.
/// Propose le scan QR Code (Recommandé) ou la saisie directe par Email + Mot de passe.
struct PairingModalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(CloudSyncEngine.self) private var syncEngine
    @Environment(ProfileStore.self) private var profiles

    enum Mode: String, CaseIterable, Identifiable {
        case qrCode = "Jumelage QR Code (Recommandé)"
        case direct = "Saisie directe"

        var id: String { rawValue }
    }

    @State private var mode: Mode = .qrCode
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var directError: String?

    var body: some View {
        ZStack {
            Theme.Palette.canvas.ignoresSafeArea()

            VStack(spacing: 32) {
                // En-tête
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Synchronisation Multi-Écrans")
                            .font(Theme.Typography.pageTitle)
                            .tracking(Theme.Typography.displayTracking)
                            .foregroundStyle(.white)
                        Text("Connectez cette Apple TV à votre compte foyer pour partager profils, favoris et historique.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }

                    Spacer()

                    Button("Fermer", systemImage: "xmark") {
                        dismiss()
                    }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                }
                .padding(.horizontal, 48)
                .padding(.top, 40)

                // Sélecteur d'onglet
                Picker("Mode de connexion", selection: $mode) {
                    ForEach(Mode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 48)
                .frame(maxWidth: 800)

                // Contenu selon le mode
                Group {
                    switch mode {
                    case .qrCode:
                        qrCodeModeView
                    case .direct:
                        directAuthModeView
                    }
                }
                .frame(maxHeight: .infinity)

                Spacer()
            }
        }
        .onAppear {
            if !auth.isAuthenticated {
                Task { await auth.startPairingSession() }
            }
        }
        .onDisappear {
            auth.stopPairingSession()
        }
        .onChange(of: auth.isAuthenticated) { _, isAuth in
            if isAuth {
                Task {
                    await syncEngine.sync()
                    profiles.requestProfilePicker()
                    dismiss()
                }
            }
        }
    }

    // MARK: - Mode QR Code (Recommandé)

    private var qrCodeModeView: some View {
        HStack(spacing: 60) {
            // QR Code à gauche
            VStack(spacing: 16) {
                if let urlString = auth.activePairingURL,
                   let qrImage = generateQRCode(from: urlString) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(14)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                } else if auth.pairingError != nil {
                    RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 248, height: 248)
                        .overlay {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(Theme.Palette.accent)
                        }
                } else {
                    RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 248, height: 248)
                        .overlay {
                            ProgressView()
                        }
                }

                Text("Scannez avec l'appareil photo")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            // Explications & Code à droite
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    stepRow(number: "1", text: "Scannez le code avec votre iPhone ou smartphone.")
                    stepRow(number: "2", text: "Créez votre compte ou connectez-vous.")
                    stepRow(number: "3", text: "Confirmez le jumelage de votre Apple TV.")
                }

                // Code en clair si demandé par le smartphone
                VStack(alignment: .leading, spacing: 6) {
                    Text("Code de jumelage :")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)

                    if let code = auth.activePairingCode {
                        Text(code)
                            .font(Theme.Typography.pageTitle.monospaced())
                            .tracking(3)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    } else {
                        Text("Génération…")
                            .font(Theme.Typography.cardTitle.monospaced())
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }

                // État de validation
                if auth.isPollingPairing {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("En attente de validation sur votre smartphone…")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.info)
                    }
                    .padding(.top, 4)
                } else if let err = auth.pairingError {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(err)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.accent)

                        Button("Générer un nouveau code") {
                            Task { await auth.startPairingSession() }
                        }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                    }
                }
            }
            .frame(maxWidth: 550, alignment: .leading)
        }
        .padding(32)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .padding(.horizontal, 48)
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(Theme.Typography.caption)
                .foregroundStyle(.black)
                .frame(width: 36, height: 36)
                .background(Color.white, in: Circle())

            Text(text)
                .font(Theme.Typography.caption)
                .foregroundStyle(.white)
        }
    }

    // MARK: - Mode Saisie Directe

    private var directAuthModeView: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Adresse Email")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)

                    TextField("nom@exemple.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .font(Theme.Typography.body)
                        .padding(14)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Mot de passe")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)

                    SecureField("••••••••••••", text: $password)
                        .textContentType(.password)
                        .font(Theme.Typography.body)
                        .padding(14)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                }
            }
            .frame(maxWidth: 500)

            if let directError {
                Text(directError)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(maxWidth: 500, alignment: .leading)
            }

            if isSubmitting {
                ProgressView("Connexion en cours…")
                    .padding()
            } else {
                HStack(spacing: 16) {
                    Button("Se connecter") {
                        Task { await handleDirectAuth(register: false) }
                    }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .disabled(email.isEmpty || password.isEmpty)

                    Button("Créer un compte") {
                        Task { await handleDirectAuth(register: true) }
                    }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                    .disabled(email.isEmpty || password.isEmpty)
                }
                .padding(.top, 10)
            }
        }
        .padding(32)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .padding(.horizontal, 48)
    }

    private func handleDirectAuth(register: Bool) async {
        isSubmitting = true
        directError = nil
        do {
            if register {
                try await auth.register(email: email, password: password)
            } else {
                try await auth.login(email: email, password: password)
            }
            await syncEngine.sync()
            profiles.requestProfilePicker()
            dismiss()
        } catch {
            directError = error.localizedDescription
        }
        isSubmitting = false
    }

    // MARK: - Générateur de QR Code

    private func generateQRCode(from string: String) -> UIImage? {
        guard !string.isEmpty, let data = string.data(using: .utf8) else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 8, y: 8)
        let scaledImage = outputImage.transformed(by: transform)

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
