import SwiftUI

/// Addon management. The LAN config server only runs while this screen is visible.
struct SettingsView: View {
    @Environment(AddonStore.self) private var addons
    @Environment(ConfigServer.self) private var server
    @State private var manualURL = ""
    @State private var manualError: String?
    /// The page stays alive when hidden, so the LAN server follows visibility explicitly.
    let isActive: Bool

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                Text("Réglages").font(Theme.Typography.pageTitle)
                remoteSection
                addonsSection
                manualSection
                Text("StremioTV \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.vertical, Theme.Spacing.l)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Palette.canvas)
        .onChange(of: isActive, initial: true) { _, active in
            if active { server.start() } else { server.stop() }
        }
        .opensRailOnExit()
    }

    private var remoteSection: some View {
        SettingsCard(title: "Gérer depuis un téléphone ou un ordinateur", symbol: "iphone.and.arrow.forward") {
            Text("Sur un appareil connecté au même Wi-Fi, ouvrez cette adresse puis saisissez le code :")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            if server.isRunning {
                HStack(spacing: Theme.Spacing.xl) {
                    labeledValue("Adresse", server.serverURLString)
                    labeledValue("Code", server.pin)
                }
            } else {
                ProgressView("Démarrage du serveur…")
            }
        }
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(label).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textTertiary)
            Text(value).font(.system(size: 34, weight: .bold, design: .monospaced))
        }
    }

    private var addonsSection: some View {
        SettingsCard(title: "Addons actifs (\(addons.urls.count))", symbol: "puzzlepiece.extension") {
            if addons.urls.isEmpty {
                Text("Aucun addon configuré. Ajoutez un addon de flux (Torrentio avec Debrid, etc.) pour pouvoir lire des contenus.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            ForEach(addons.urls, id: \.self) { url in
                HStack {
                    Label(AddonStore.maskedDisplay(url), systemImage: "checkmark.seal.fill")
                        .font(Theme.Typography.cardTitle)
                    Spacer()
                    Button("Supprimer", systemImage: "trash", role: .destructive) { addons.remove(url) }
                        .buttonStyle(PillButtonStyle())
                }
            }
        }
    }

    private var manualSection: some View {
        SettingsCard(title: "Ajouter une URL manuellement", symbol: "keyboard") {
            HStack(spacing: Theme.Spacing.m) {
                TextField("https://…/manifest.json", text: $manualURL)
                    .textContentType(.URL)
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
                Text(manualError).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.accent)
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Label(title, systemImage: symbol).font(Theme.Typography.rowTitle)
            content
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .focusSection()
    }
}
