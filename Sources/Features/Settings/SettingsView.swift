import SwiftUI
import CoreImage

/// Page Réglages de StremioTV sur tvOS : page unique structurée en sections claires,
/// avec sélecteurs de langues compacts (options cachées dans un Menu popover natif).
struct SettingsView: View {
    @Environment(AddonStore.self) private var addons
    @Environment(ConfigServer.self) private var server
    @Environment(AuthService.self) private var auth
    @Environment(CloudSyncEngine.self) private var syncEngine
    @State private var preferences = AppPreferences.shared
    @State private var manualURL = ""
    @State private var manualError: String?
    @State private var isShowingPairingSheet = false

    /// Le serveur LAN ne tourne que lorsque cet écran est affiché.
    let isActive: Bool

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 40) {
                // En-tête principal
                VStack(alignment: .leading, spacing: 6) {
                    Text("Réglages")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Personnalisez vos métadonnées, pistes de lecture et extensions")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .padding(.top, 16)

                // Section 0 : Compte & Synchronisation Foyer
                SettingsSectionCard(title: "Compte & Synchronisation Foyer", symbol: "icloud.fill") {
                    cloudSyncContent
                }

                // Section 1 : Général & Métadonnées
                SettingsSectionCard(title: "Général & Métadonnées", symbol: "globe") {
                    languageMenuRow(
                        title: "Langue des métadonnées",
                        subtitle: "Titres, résumés et castings fournis par TMDB et Cinemeta",
                        selectedCode: preferences.metadataLanguage
                    ) { code in
                        preferences.metadataLanguage = code
                    }
                }

                // Section 2 : Lecture & Audio
                SettingsSectionCard(title: "Lecture & Audio", symbol: "speaker.wave.2.fill") {
                    VStack(spacing: 12) {
                        languageMenuRow(
                            title: "Langue audio préférée",
                            subtitle: "Piste sonore sélectionnée par défaut lors du lancement d'une vidéo",
                            selectedCode: preferences.preferredAudioLanguage
                        ) { code in
                            preferences.preferredAudioLanguage = code
                        }

                        subtitleModeMenuRow

                        if preferences.subtitleMode != .off {
                            languageMenuRow(
                                title: "Langue des sous-titres préférée",
                                subtitle: "Langue utilisée pour l'activation automatique des sous-titres",
                                selectedCode: preferences.preferredSubtitleLanguage
                            ) { code in
                                preferences.preferredSubtitleLanguage = code
                            }
                        }
                    }
                }

                // Section 3 : Gestion à distance (Compagnon Web)
                SettingsSectionCard(title: "Gestion à distance (Compagnon Web)", symbol: "iphone.and.arrow.forward") {
                    remoteCompanionContent
                }

                // Section 4 : Extensions & Addons
                SettingsSectionCard(title: "Extensions & Addons (\(addons.urls.count))", symbol: "puzzlepiece.extension.fill") {
                    addonsContent
                }

                // Section 5 : À propos
                SettingsSectionCard(title: "À propos", symbol: "info.circle.fill") {
                    aboutContent
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Palette.canvas.ignoresSafeArea())
        .onChange(of: isActive, initial: true) { _, active in
            if active { server.start() } else { server.stop() }
        }
        .sheet(isPresented: $isShowingPairingSheet) {
            PairingModalSheet()
        }
        .opensRailOnExit()
    }

    // MARK: - Section Compte & Synchronisation Cloud

    private var cloudSyncContent: some View {
        Group {
            if auth.isAuthenticated {
                HStack(spacing: 24) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.green)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(auth.accountEmail ?? "Compte connecté")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)

                        if syncEngine.isSyncing {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Synchronisation en cours…")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.cyan)
                            }
                        } else if let err = syncEngine.syncError {
                            Text("Erreur : \(err)")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.Palette.accent)
                        } else if let date = syncEngine.lastSyncDate {
                            Text("Dernière synchro : \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        } else {
                            Text("Synchronisation active sur toutes les Apple TV")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }

                    Spacer()

                    Button("Synchroniser", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await syncEngine.sync() }
                    }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .disabled(syncEngine.isSyncing)

                    Button("Déconnexion", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        auth.logout()
                    }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                }
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reliez toutes les Apple TV du foyer")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Partagez vos profils, votre historique « Reprendre », vos favoris et vos extensions entre vos différentes Apple TV.")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }

                    Spacer()

                    Button("Activer la synchronisation", systemImage: "link") {
                        isShowingPairingSheet = true
                    }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Sélecteurs de Langues (Menu natif tvOS avec options cachées)

    private func languageMenuRow(
        title: String,
        subtitle: String,
        selectedCode: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        Menu {
            ForEach(SupportedLanguage.all) { lang in
                Button {
                    onSelect(lang.code)
                } label: {
                    if selectedCode == lang.code {
                        Label(lang.name, systemImage: "checkmark")
                    } else {
                        Text(lang.name)
                    }
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    Text(SupportedLanguage.name(for: selectedCode))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.cyan)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
        .buttonStyle(SettingsRowButtonStyle())
    }

    private var subtitleModeMenuRow: some View {
        Menu {
            ForEach(SubtitlePreferenceMode.allCases, id: \.self) { mode in
                Button {
                    preferences.subtitleMode = mode
                } label: {
                    if preferences.subtitleMode == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activation des sous-titres")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitleModeDescription)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    Text(preferences.subtitleMode.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.cyan)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
        .buttonStyle(SettingsRowButtonStyle())
    }

    private var subtitleModeDescription: String {
        switch preferences.subtitleMode {
        case .auto:
            return "Active les sous-titres complets si l'audio est étranger, ou forcés si l'audio est déjà dans votre langue."
        case .alwaysOn:
            return "Active systématiquement les sous-titres dans votre langue préférée, quel que soit l'audio."
        case .off:
            return "Désactive les sous-titres par défaut (activables manuellement pendant la lecture)."
        }
    }

    // MARK: - Section Gestion à Distance

    private var remoteCompanionContent: some View {
        Group {
            if server.isRunning {
                HStack(spacing: 36) {
                    if let qrImage = generateQRCode(from: server.serverURLString) {
                        VStack(spacing: 8) {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 150, height: 150)
                                .padding(10)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))

                            Text("Scannez à l'iPhone")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("1. Ouvrez l'adresse sur votre téléphone ou PC :")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(server.serverURLString)
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.cyan)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("2. Saisissez le code PIN :")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(server.pin)
                                .font(.system(size: 36, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        }

                        HStack(spacing: 8) {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text("Serveur local actif sur le même Wi-Fi")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            } else {
                ProgressView("Démarrage du serveur compagnon…")
                    .padding()
            }
        }
    }

    // MARK: - Section Addons

    private var addonsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if addons.urls.isEmpty {
                Text("Aucun addon configuré. Utilisez le compagnon web ou saisissez une URL ci-dessous.")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Palette.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(addons.urls, id: \.self) { url in
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Color.green)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(AddonStore.maskedDisplay(url))
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(url)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(Theme.Palette.textTertiary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button("Supprimer", systemImage: "trash", role: .destructive) {
                                addons.remove(url)
                            }
                            .buttonStyle(PillButtonStyle(kind: .secondary))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }

            // Saisie URL manuelle
            HStack(spacing: 12) {
                TextField("https://.../manifest.json", text: $manualURL)
                    .textContentType(.URL)
                    .font(.system(size: 18))
                    .padding(12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                Button("Ajouter", systemImage: "plus") {
                    if addons.add(manualURL) {
                        manualURL = ""
                        manualError = nil
                    } else {
                        manualError = "URL invalide : elle doit commencer par https://"
                    }
                }
                .buttonStyle(PillButtonStyle(kind: .primary))
                .disabled(manualURL.isEmpty)
            }

            if let manualError {
                Text(manualError)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Palette.accent)
            }
        }
    }

    // MARK: - Section À Propos

    private var aboutContent: some View {
        VStack(spacing: 8) {
            aboutRow(label: "Version", value: "StremioTV 2.0 (Build 1)")
            aboutRow(label: "Moteur vidéo", value: "Lecteur natif AVKit + TVVLCKit")
            aboutRow(label: "Métadonnées", value: "TMDB API v3 & Cinemeta")
            aboutRow(label: "Stockage partagé", value: "App Group com.h6245.vortxtv")
        }
    }

    private func aboutRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 4)
    }

    // MARK: - QR Code Helper

    private func generateQRCode(from string: String) -> UIImage? {
        guard !string.isEmpty, let data = string.data(using: .utf8) else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 6, y: 6)
        let scaledImage = outputImage.transformed(by: transform)

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Composants UI modulaires

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: symbol)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)

            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .focusSection()
    }
}

private struct SettingsRowButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isFocused {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.20))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.2)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.03))
                }
            }
            .scaleEffect(Theme.Motion.scale(focused: isFocused, pressed: configuration.isPressed, focusScale: 1.02, reduceMotion: reduceMotion))
            .animation(Theme.Motion.focus, value: isFocused)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}
