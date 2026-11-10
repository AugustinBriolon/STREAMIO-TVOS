import SwiftUI

/// Create or edit a profile: name, color, symbol, and (when editing) delete.
struct ProfileEditorView: View {
    let target: ProfileEditorTarget

    @Environment(ProfileStore.self) private var profiles
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var avatar = ProfileAvatar(color: .blue, symbol: .face)
    @State private var errorMessage: String?
    @State private var confirmsDelete = false
    @State private var didLoad = false

    private var editedProfile: Profile? {
        if case .edit(let profile) = target { return profile }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xxl) {
            VStack(spacing: Theme.Spacing.m) {
                ProfileAvatarView(avatar: avatar, size: 260)
                Text(name.isEmpty ? "Nouveau profil" : name)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 320)

            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text(editedProfile == nil ? "Ajouter un profil" : "Modifier le profil")
                    .font(Theme.Typography.pageTitle)
                TextField("Nom du profil", text: $name)
                    .font(Theme.Typography.body)
                    .onSubmit(save)
                section("Couleur") { colorRow }
                section("Pictogramme") { symbolRow }
                if let errorMessage {
                    Text(errorMessage).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.accent)
                }
                actions
            }
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .padding(Theme.Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.canvas)
        .onAppear(perform: load)
        .onExitCommand { dismiss() }
        .confirmationDialog(
            "Supprimer le profil « \(editedProfile?.name ?? "") » ?",
            isPresented: $confirmsDelete, titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive, action: delete)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Sa liste et sa progression de lecture seront perdues. Cette action est définitive.")
        }
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textSecondary)
            content()
        }
        .focusSection()
    }

    private var colorRow: some View {
        HStack(spacing: Theme.Spacing.m) {
            ForEach(AvatarColor.allCases, id: \.self) { color in
                Button { avatar.color = color } label: {
                    Circle().fill(color.color).frame(width: 64, height: 64)
                        .overlay {
                            if avatar.color == color {
                                Image(systemName: "checkmark").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(AvatarButtonStyle())
                .accessibilityLabel(color.rawValue)
                .accessibilityAddTraits(avatar.color == color ? .isSelected : [])
            }
        }
    }

    private var symbolRow: some View {
        HStack(spacing: Theme.Spacing.m) {
            ForEach(AvatarSymbol.allCases, id: \.self) { symbol in
                Button { avatar.symbol = symbol } label: {
                    Image(systemName: symbol.rawValue)
                        .font(.system(size: 30, weight: .semibold))
                        .frame(width: 64, height: 64)
                        .foregroundStyle(avatar.symbol == symbol ? Color.black : Theme.Palette.textPrimary)
                        .background(avatar.symbol == symbol ? Color.white : Theme.Palette.surfaceRaised, in: Circle())
                }
                .buttonStyle(AvatarButtonStyle())
                .accessibilityLabel(symbol.rawValue)
                .accessibilityAddTraits(avatar.symbol == symbol ? .isSelected : [])
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button("Enregistrer", systemImage: "checkmark", action: save)
                .buttonStyle(PillButtonStyle(kind: .primary))
            Button("Annuler") { dismiss() }
                .buttonStyle(PillButtonStyle())
            if editedProfile != nil, profiles.profiles.count > 1 {
                Button("Supprimer", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .focusSection()
    }

    // MARK: Behavior

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let profile = editedProfile {
            name = profile.name
            avatar = profile.avatar
        } else {
            name = "Profil \(profiles.profiles.count + 1)"
            avatar = .suggested(avoiding: profiles.profiles)
        }
    }

    private func save() {
        do {
            if let profile = editedProfile {
                try profiles.update(profile.id, name: name, avatar: avatar)
            } else {
                try profiles.create(name: name, avatar: avatar)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        guard let profile = editedProfile else { return }
        do {
            try profiles.delete(profile.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
