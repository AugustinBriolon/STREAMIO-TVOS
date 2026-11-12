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
    @Environment(\.railBlocker) private var railBlocker
    @State private var preferences = AppPreferences.shared
    @State private var manualURL = ""
    @State private var manualError: String?
    @State private var isShowingPairingSheet = false
    @State private var confirmsDeleteAccount = false
    @State private var deleteAccountError: String?
    @State private var isDeletingAccount = false
    @State private var showsPaywall = false
    @State private var addonPendingDelete: String?
    @State private var section: SettingsSection = .account
    @FocusState private var focusedSection: SettingsSection?

    /// Le serveur LAN ne tourne que lorsque cet écran est affiché.
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            sidebar
            // Recreate the pane on section change so scroll stays top-aligned with the sidebar:
            // a tall block above the first focusable made left-exit jump to the nav rail instead.
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
                .id(section)
            }
            .scrollIndicators(.hidden)
            .focusSection()
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .background(Theme.Palette.canvas.ignoresSafeArea())
        .onChange(of: isActive, initial: true) { _, active in
            if !active { railBlocker.detailBlocksRail = false }
            updateCompanionServer()
        }
        .onChange(of: section) { _, _ in updateCompanionServer() }
        // Sidebar: rail reachable. Detail: block rail. Leaving sidebar for the rail must NOT block
        // (that disabled the icons mid-focus and trapped navigation on Accueil).
        .onChange(of: focusedSection) { old, new in
            if let new {
                railBlocker.detailBlocksRail = false
                if old == nil, new != section {
                    focusedSection = section
                } else {
                    section = new
                }
            } else if old != nil {
                Task { @MainActor in
                    await Task.yield()
                    guard isActive, focusedSection == nil, !railBlocker.railFocused else { return }
                    railBlocker.detailBlocksRail = true
                }
            }
        }
        .sheet(isPresented: $isShowingPairingSheet) {
            PairingModalSheet()
        }
        .confirmationDialog(
            "Supprimer le compte ?",
            isPresented: $confirmsDeleteAccount,
            titleVisibility: .visible
        ) {
            Button("Supprimer le compte", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Profils, Ma liste, progression et appareils synchronisés seront effacés immédiatement. Cette action est définitive.")
        }
        .alert("Suppression impossible", isPresented: Binding(
            get: { deleteAccountError != nil },
            set: { if !$0 { deleteAccountError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteAccountError ?? "")
        }
        .confirmationDialog(
            "Supprimer cette extension ?",
            isPresented: Binding(
                get: { addonPendingDelete != nil },
                set: { if !$0 { addonPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let url = addonPendingDelete {
                    addons.remove(url)
                }
                addonPendingDelete = nil
            }
            Button("Annuler", role: .cancel) {
                addonPendingDelete = nil
            }
        } message: {
            if let url = addonPendingDelete {
                Text(AddonStore.displayTitle(url))
            }
        }
        .opensRailOnExit()
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await auth.deleteAccount()
            // Account already gone remotely; wipe local foyer after credentials are cleared.
            syncEngine.clearLocalHousehold()
        } catch {
            deleteAccountError = error.localizedDescription
        }
    }

    private func signOut() {
        // Drop the token first so RootView's onChange(profiles) cannot push the wiped guest foyer.
        auth.logout()
        syncEngine.clearLocalHousehold()
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
        guard entry == .addons else { return entry.title }
        let limits = PlanLimits.forPlan(addons.plan)
        return "\(entry.title) · \(addons.personalAddonCount)/\(limits.maxAddons)"
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
        case .addons:
            addonsContent
        case .about:
            aboutContent
        }
    }

    /// LAN companion is only for pasting addon URLs; keep the port closed outside Extensions.
    private func updateCompanionServer() {
        if isActive, section == .addons {
            server.start()
        } else {
            server.stop()
        }
    }

    // MARK: - Section Compte & Synchronisation Cloud

    private var cloudSyncContent: some View {
        Group {
            if auth.isAuthenticated {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    accountIdentityRow
                    accountActionsRow
                    currentPlanSummary
                    devicesList
                }
            } else {
                HStack(alignment: .center, spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Reliez toutes les Apple TV du foyer")
                            .font(Theme.Typography.cardTitle)
                            .foregroundStyle(.white)
                        Text("Partagez vos profils, votre historique « Reprendre », vos favoris et vos extensions entre vos différentes Apple TV. Les offres Pro et Ultra se gèrent avec un compte.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Activer la synchronisation", systemImage: "link") {
                        isShowingPairingSheet = true
                    }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
    }

    private var accountIdentityRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 40))
                .foregroundStyle(Color.green)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(auth.accountEmail ?? "Compte connecté")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(.white)
                accountSyncStatus
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var accountSyncStatus: some View {
        if syncEngine.isSyncing {
            HStack(spacing: Theme.Spacing.s) {
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
            Text("Synchronisation active sur le foyer")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private var accountActionsRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            Button("Synchroniser", systemImage: "arrow.triangle.2.circlepath") {
                Task { await syncEngine.sync() }
            }
            .buttonStyle(PillButtonStyle(kind: .primary))
            .disabled(syncEngine.isSyncing)

            Button("Déconnexion", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                signOut()
            }
            .buttonStyle(PillButtonStyle(kind: .secondary))
            .disabled(isDeletingAccount)

            Button("Supprimer le compte", systemImage: "trash", role: .destructive) {
                confirmsDeleteAccount = true
            }
            .buttonStyle(PillButtonStyle(kind: .secondary))
            .disabled(isDeletingAccount)

            Spacer(minLength: 0)
        }
    }

    private var currentPlanSummary: some View {
        HStack(spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Offre \(planLabel(auth.plan))")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(planSummary(auth.plan))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            Button(auth.plan == .ultra ? "Gérer l’offre" : "Voir les offres", systemImage: "sparkles") {
                showsPaywall = true
            }
            .buttonStyle(PillButtonStyle(kind: .primary))
        }
        .padding(.vertical, Theme.Spacing.s)
        .fullScreenCover(isPresented: $showsPaywall) {
            SubscriptionPaywallView()
        }
    }

    private func planLabel(_ plan: LogePlan) -> String {
        switch plan {
        case .free: "Free"
        case .pro: "Pro"
        case .ultra: "Ultra"
        }
    }

    private func planSummary(_ plan: LogePlan) -> String {
        let limits = PlanLimits.forPlan(plan)
        let sync = limits.cloudSync ? "sync cloud" : "local uniquement"
        return "\(limits.maxProfiles) profils · \(limits.maxAddons) extensions installables · \(limits.maxTVSessions) Apple TV · \(limits.maxBrowserSessions) navigateur · \(sync)"
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
                    Image(systemName: device.systemSymbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 36, alignment: .center)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(device.name)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(deviceSubtitle(device))
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
                .accessibilityLabel("\(device.name), \(deviceSubtitle(device))")
            }
            Text("Pour déconnecter un appareil, ouvrez votre espace en ligne : \(auth.apiBaseURL)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(.top, Theme.Spacing.m)
        .task { await auth.refreshDevices() }
    }

    private func deviceSubtitle(_ device: DeviceSession) -> String {
        let kindLabel = device.isBrowser ? "Navigateur" : "Apple TV"
        return [kindLabel, device.model, device.lastSeen.map { "Vu \($0.formatted(.relative(presentation: .named)))" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
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

    // MARK: - Section Addons

    private var addonsContent: some View {
        let limits = PlanLimits.forPlan(addons.plan)
        let personal = addons.personalURLs
        let included = addons.includedURLs

        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Loge ne fournit aucun flux. Les inclus sont toujours là (on/off). Seules les installées comptent dans l’offre et se suppriment.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)

            // MARK: Incluses (offre Loge — hors quota)
            extensionSectionHeader(
                "Incluses",
                detail: "Toujours présentes · clic = on/off · hors quota"
            )
            extensionRow(
                title: "Disponibilité plateformes",
                subtitle: "Netflix, Disney+, Prime… sur la fiche (TMDB)",
                isOn: preferences.showWatchProviders,
                kind: .included
            ) {
                preferences.showWatchProviders.toggle()
            } onRequestDelete: {}

            ForEach(included, id: \.self) { url in
                extensionRow(
                    title: AddonStore.displayTitle(url),
                    subtitle: AddonStore.maskedDisplay(url),
                    isOn: addons.isEnabled(url),
                    kind: .included
                ) {
                    addons.toggle(url)
                } onRequestDelete: {}
            }

            if included.isEmpty {
                Text("YouTube et OpenSubtitles absents — déconnexion / réinstall les restaure.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            // MARK: Installées (quota offre)
            extensionSectionHeader(
                "Installées",
                detail: "\(personal.count) / \(limits.maxAddons) · maintien = supprimer · comptent dans \(planLabel(addons.plan))"
            )

            ForEach(personal, id: \.self) { url in
                extensionRow(
                    title: AddonStore.displayTitle(url),
                    subtitle: AddonStore.maskedDisplay(url),
                    isOn: addons.isEnabled(url),
                    kind: .installable
                ) {
                    addons.toggle(url)
                } onRequestDelete: {
                    addonPendingDelete = url
                }
            }

            if personal.isEmpty {
                Text("Aucune extension installée pour l’instant.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }

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
                        manualError = addons.canAdd
                            ? "URL invalide : elle doit commencer par https://"
                            : "Quota d’installées atteint (\(limits.maxAddons) pour \(planLabel(addons.plan))). Les inclus ne comptent pas."
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

            // Below the list so the first focusable rows stay Y-aligned with the sidebar.
            phoneKeyboardHelper
                .padding(.top, Theme.Spacing.l)
        }
    }

    private func extensionSectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(.top, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
    }

    /// Same Wi‑Fi page to paste a long addon URL — not the online account portal.
    private var phoneKeyboardHelper: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Coller une URL depuis le téléphone")
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(phoneKeyboardPurpose)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

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
                            Text("1. Même Wi‑Fi — ouvrez :")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.white)
                            Text(server.serverURLString)
                                .font(Theme.Typography.cardTitle.monospaced())
                                .foregroundStyle(Theme.Palette.info)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("2. PIN affiché ici :")
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
                            Text("Page locale active tant que Réglages → Extensions est ouvert")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            } else {
                ProgressView("Préparation de la page locale…")
                    .padding(.vertical, Theme.Spacing.s)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var phoneKeyboardPurpose: String {
        if auth.isAuthenticated, auth.limits.cloudSync {
            return "L’espace en ligne (\(auth.apiBaseURL)) gère les extensions du foyer sur toutes les Apple TV. Cette page Wi‑Fi locale ne sert qu’à coller une URL longue sur cette TV, sans le clavier de la télécommande."
        }
        if auth.isAuthenticated {
            return "Sans sync cloud (Free), les extensions restent sur cette Apple TV. Utilisez cette page Wi‑Fi pour coller une URL depuis le téléphone — ce n’est pas l’espace compte en ligne."
        }
        return "Pour éviter le clavier de la télécommande : ouvrez l’adresse sur votre téléphone (même Wi‑Fi), entrez le PIN, collez l’URL de l’extension. L’espace compte en ligne sert au foyer connecté, pas à coller une URL ici."
    }

    private enum ExtensionKind {
        case included
        case installable
    }

    /// Rangée unique : inclus (on/off only) vs installable (on/off + maintien supprimer).
    /// tvOS: `contextMenu` sur Button+scale presse bloque le maintien — `Menu`+`primaryAction`.
    @ViewBuilder
    private func extensionRow(
        title: String,
        subtitle: String,
        isOn: Bool,
        kind: ExtensionKind,
        onToggle: @escaping () -> Void,
        onRequestDelete: @escaping () -> Void
    ) -> some View {
        let label = HStack(spacing: Theme.Spacing.m) {
            Image(systemName: isOn ? "checkmark.seal.fill" : "seal")
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(isOn ? Color.green : Theme.Palette.textTertiary)
                .frame(width: 36, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(isOn ? "Activée" : "Masquée")
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(isOn ? Theme.Palette.info : Theme.Palette.textTertiary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .accessibilityLabel("\(title), \(kind == .included ? "incluse" : "installée"), \(isOn ? "activée" : "masquée")")

        if kind == .installable {
            Menu(content: {
                Button("Supprimer", systemImage: "trash", role: .destructive, action: onRequestDelete)
            }, label: {
                label
            }, primaryAction: {
                onToggle()
            })
            .buttonStyle(SettingsRowButtonStyle(scalesOnPress: false))
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .accessibilityHint("Maintien pour supprimer")
        } else {
            Button(action: onToggle) { label }
                .buttonStyle(SettingsRowButtonStyle(scalesOnPress: false))
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityHint("Toujours installée, non supprimable")
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
    case account, metadata, playback, addons, about

    var id: Self { self }

    var title: String {
        switch self {
        case .account: "Compte & synchronisation"
        case .metadata: "Métadonnées"
        case .playback: "Lecture & audio"
        case .addons: "Extensions"
        case .about: "À propos"
        }
    }

    var symbol: String {
        switch self {
        case .account: "icloud.fill"
        case .metadata: "globe"
        case .playback: "speaker.wave.2.fill"
        case .addons: "puzzlepiece.extension.fill"
        case .about: "info.circle.fill"
        }
    }
}

private struct SettingsRowButtonStyle: ButtonStyle {
    /// The sidebar entry whose content is showing keeps a quiet highlight while focus is elsewhere.
    var isSelected = false
    /// Off for rows that use long-press: `isPressed` stays true on tvOS and leaves a stuck shrink.
    var scalesOnPress = true
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = scalesOnPress && configuration.isPressed
        return configuration.label
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
            .scaleEffect(Theme.Motion.scale(focused: isFocused, pressed: pressed, focusScale: 1.02, reduceMotion: reduceMotion))
            .animation(Theme.Motion.focus, value: isFocused)
            .animation(Theme.Motion.press, value: pressed)
    }
}
