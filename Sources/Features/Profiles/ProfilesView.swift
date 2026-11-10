import SwiftUI

/// "Qui regarde ?": switch profile, or manage them (add, edit, delete).
struct ProfilesView: View {
    @Environment(ProfileStore.self) private var profiles
    /// Called after a profile was chosen, so the app can go back to the home page.
    let onSwitched: () -> Void

    @State private var isManaging = false
    @State private var editing: ProfileEditorTarget?
    @FocusState private var focus: UUID?

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: Theme.Spacing.xl)]

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Text(isManaging ? "Gérer les profils" : "Qui regarde ?")
                .font(Theme.Typography.pageTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            LazyVGrid(columns: columns, spacing: Theme.Spacing.xl) {
                ForEach(profiles.profiles) { profile in
                    ProfileCard(profile: profile, isActive: profile.id == profiles.activeID, isManaging: isManaging) {
                        if isManaging {
                            editing = .edit(profile)
                        } else {
                            profiles.select(profile.id)
                            onSwitched()
                        }
                    }
                }
                if profiles.canAdd {
                    AddProfileCard { editing = .create }
                }
            }
            .frame(maxWidth: 1400)
            .focusSection()
            Button(isManaging ? "Terminé" : "Gérer les profils", systemImage: isManaging ? "checkmark" : "pencil") {
                isManaging.toggle()
            }
            .buttonStyle(PillButtonStyle(kind: isManaging ? .primary : .secondary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.canvas)
        .opensRailOnExit()
        .fullScreenCover(item: $editing) { target in
            ProfileEditorView(target: target)
        }
    }
}

enum ProfileEditorTarget: Identifiable {
    case create
    case edit(Profile)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let profile): return profile.id.uuidString
        }
    }
}

private struct ProfileCard: View {
    let profile: Profile
    let isActive: Bool
    let isManaging: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.s) {
                ProfileAvatarView(avatar: profile.avatar, size: 180)
                    .overlay(alignment: .bottomTrailing) {
                        if isManaging {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 54))
                                .foregroundStyle(.white, Theme.Palette.accent)
                                .offset(x: 4, y: 4)
                        }
                    }
                Text(profile.name)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(isActive ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                    .lineLimit(1)
                Text(isActive ? "Profil actif" : " ")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.accent)
            }
            .frame(width: 220)
        }
        .buttonStyle(AvatarButtonStyle())
        .accessibilityLabel(isManaging ? "Modifier \(profile.name)" : profile.name)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct AddProfileCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.s) {
                Circle()
                    .strokeBorder(Theme.Palette.textTertiary, style: StrokeStyle(lineWidth: 4, dash: [14, 10]))
                    .frame(width: 180, height: 180)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 76, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                Text("Ajouter un profil")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text(" ").font(Theme.Typography.caption)
            }
            .frame(width: 220)
        }
        .buttonStyle(AvatarButtonStyle())
        .accessibilityLabel("Ajouter un profil")
    }
}
