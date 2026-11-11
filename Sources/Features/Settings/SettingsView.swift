import SwiftUI
import CoreImage

/// Settings, laid out like the system Settings app: sections on the left, the focused section's
/// content on the right. Every section is reachable even when it holds nothing clickable
/// (a single scrolling page skipped those: the focus engine jumped over them).
struct SettingsView: View {
    @Environment(AddonStore.self) private var addons
    @Environment(ConfigServer.self) private var server
    @Environment(AuthService.self) private var auth
    @Environment(CloudSyncEngine.self) private var syncEngine
    @State private var preferences = AppPreferences.shared
    @State private var manualURL = ""
    @State private var manualError: String?
    @State private var isShowingPairingSheet = false
    @State private var section: SettingsSection = .account
    @FocusState private var focusedSection: SettingsSection?

    /// Le serveur LAN ne tourne que lorsque cet écran est affiché.
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            sidebar
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Label(title(for: section), systemImage: section.symbol)
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    content(for: section)
                }
                .padding(Theme.Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Palette.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                .padding(.vertical, Theme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .focusSection()
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .background(Theme.Palette.canvas.ignoresSafeArea())
        .onChange(of: isActive, initial: true) { _, active in
            if active { server.start() } else { server.stop() }
        }
        // The detail pane follows the focused entry. Coming back from the detail pane lands on the
        // entry being shown, not on whichever one is nearest in height.
        .onChange(of: focusedSection) { old, new in
            guard let new else { return }
            if old == nil, new != section {
                focusedSection = section
            } else {
                section = new
            }
        }
        .sheet(isPresented: $isShowingPairingSheet) {
            PairingModalSheet()
        }
        .opensRailOnExit()
    }

    /// Left column: one entry per section, like the system Settings app.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Réglages")
                .font(Theme.Typography.pageTitle)
                .tracking(Theme.Typography.displayTracking)
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.bottom, Theme.Spacing.m)
            ForEach(SettingsSection.allCases) { entry in
                Button { section = entry } label: {
                    Label(title(for: entry), systemImage: entry.symbol)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(SettingsRowButtonStyle(isSelected: entry == section))
                .focused($focusedSection, equals: entry)
                .accessibilityAddTraits(entry == section ? .isSelected : [])
            }
        }
        .frame(width: 560)
        .padding(.top, Theme.Spacing.xl)
        .focusSection()
    }

    private func title(for entry: SettingsSection) -> String {
        entry == .addons ? "\(entry.title) (\(addons.urls.count))" : entry.title
    }

    @ViewBuilder
    private func content(for entry: SettingsSection) -> some View {
        switch entry {
        case .account:
            cloudSyncContent
        case .metadata:
            languageMenuRow(
                title: "Langue des métadonnées",
                subtitle: "Titres, résumés et castings fournis par TMDB et Cinemeta",
                selectedCode: preferences.metadataLanguage
            ) { preferences.metadataLanguage = $0 }
        case .playback:
            VStack(spacing: Theme.Spacing.s) {
                languageMenuRow(
                    title: "Langue audio préférée",
                    subtitle: "Piste sonore sélectionnée par défaut lors du lancement d'une vidéo",
                    selectedCode: preferences.preferredAudioLanguage
                ) { preferences.preferredAudioLanguage = $0 }
                subtitleModeMenuRow
                if preferences.subtitleMode != .off {
                    languageMenuRow(
                        title: "Langue des sous-titres préférée",
                        subtitle: "Langue utilisée pour l'activation automatique des sous-titres",
                        selectedCode: preferences.preferredSubtitleLanguage
                    ) { preferences.preferredSubtitleLanguage = $0 }
                }
            }
        case .companion:
            remoteCompanionContent
        case .addons:
            addonsContent
        case .about:
            aboutContent
        }
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
                            .font(Theme.Typography.cardTitle)
                            .foregroundStyle(.white)

                        if syncEngine.isSyncing {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Synchronisation en cours…")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Palette.info)
                            }
                        } else if let err = syncEngine.syncError {
                            Text("Erreur : \(err)")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.accent)
                        } else if let date = syncEngine.lastSyncDate {
                            Text("Dernière synchro : \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        } else {
                            Text("Synchronisation active sur toutes les Apple TV")
                                .font(Theme.Typography.caption)
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
                devicesList
            } else {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reliez toutes les Apple TV du foyer")
                            .font(Theme.Typography.cardTitle)
                            .foregroundStyle(.white)
                        Text("Partagez vos profils, votre historique « Reprendre », vos favoris et vos extensions entre vos différentes Apple TV.")
                            .font(Theme.Typography.caption)
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

    /// Devices signed in to the account. Read-only here: they are signed out from the online account page.
    private var devicesList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Appareils connectés")
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            if auth.devices.isEmpty {
                Text("Les appareils connectés avant cette version n'apparaissent qu'après une nouvelle connexion.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            ForEach(auth.devices) { device in
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "appletv.fill")
                        .foregroundStyle(Theme.Palette.textSecondary)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(device.name)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text([device.model, device.lastSeen.map { "Vu \($0.formatted(.relative(presentation: .named)))" }]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                    if device.isCurrent {
                        Text("Cet appareil")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.info)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Text("Pour déconnecter un appareil, ouvrez votre espace en ligne : \(auth.apiBaseURL)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(.top, Theme.Spacing.m)
        .task { await auth.refreshDevices() }
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
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    Text(SupportedLanguage.name(for: selectedCode))
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.info)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(Theme.Typography.caption)
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
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(.white)
                    Text(subtitleModeDescription)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    Text(preferences.subtitleMode.title)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.info)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(Theme.Typography.caption)
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
                                .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))

                            Text("Scannez à l'iPhone")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("1. Ouvrez l'adresse sur votre téléphone ou PC :")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.white)
                            Text(server.serverURLString)
                                .font(Theme.Typography.cardTitle.monospaced())
                                .foregroundStyle(Theme.Palette.info)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("2. Saisissez le code PIN :")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.white)
                            Text(server.pin)
                                .font(Theme.Typography.pageTitle.monospaced())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                        }

                        HStack(spacing: 8) {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text("Serveur local actif sur le même Wi-Fi")
                                .font(Theme.Typography.caption)
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
        .accessibilityElement(children: .combine)
    }

    // MARK: - Section Addons

    private var addonsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Loge ne fournit aucun flux. Ajoutez uniquement des addons et sources auxquels vous avez légalement accès.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)

            if addons.urls.isEmpty {
                Text("Aucun addon configuré. Utilisez le compagnon web ou saisissez une URL ci-dessous.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(addons.urls, id: \.self) { url in
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .font(Theme.Typography.cardTitle)
                                .foregroundStyle(Color.green)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(AddonStore.maskedDisplay(url))
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(.white)
                                Text(url)
                                    .font(Theme.Typography.caption.monospaced())
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
                        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    }
                }
            }

            // Saisie URL manuelle
            HStack(spacing: 12) {
                TextField("https://.../manifest.json", text: $manualURL)
                    .textContentType(.URL)
                    .font(Theme.Typography.body)
                    .padding(12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))

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
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.accent)
            }
        }
    }

    // MARK: - Section À Propos

    private var aboutContent: some View {
        VStack(spacing: 8) {
            aboutRow(label: "Version", value: "Loge 2.0")
            aboutRow(label: "Moteur vidéo", value: "libVLC (TVVLCKit)")
            aboutRow(label: "Métadonnées", value: "TMDB API v3 & Cinemeta")
            aboutRow(label: "Stockage partagé", value: "App Group Loge")
        }
    }

    private func aboutRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Typography.caption)
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

enum SettingsSection: CaseIterable, Identifiable {
    case account, metadata, playback, companion, addons, about

    var id: Self { self }

    var title: String {
        switch self {
        case .account: "Compte & synchronisation"
        case .metadata: "Métadonnées"
        case .playback: "Lecture & audio"
        case .companion: "Gestion à distance"
        case .addons: "Extensions"
        case .about: "À propos"
        }
    }

    var symbol: String {
        switch self {
        case .account: "icloud.fill"
        case .metadata: "globe"
        case .playback: "speaker.wave.2.fill"
        case .companion: "iphone.and.arrow.forward"
        case .addons: "puzzlepiece.extension.fill"
        case .about: "info.circle.fill"
        }
    }
}

private struct SettingsRowButtonStyle: ButtonStyle {
    /// The sidebar entry whose content is showing keeps a quiet highlight while focus is elsewhere.
    var isSelected = false
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isFocused {
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(Color.white.opacity(0.20))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.2)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(Color.white.opacity(isSelected ? 0.12 : 0.03))
                }
            }
            .scaleEffect(Theme.Motion.scale(focused: isFocused, pressed: configuration.isPressed, focusScale: 1.02, reduceMotion: reduceMotion))
            .animation(Theme.Motion.focus, value: isFocused)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}
