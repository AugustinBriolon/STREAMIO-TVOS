import SwiftUI

/// "Qui regarde ?": switch profile, or manage them (add, edit, delete).
struct ProfilesView: View {
    @Environment(ProfileStore.self) private var profiles
    /// Called after a profile was chosen, so the app can go back to the home page.
    let onSwitched: () -> Void

    @State private var isManaging = false
    @State private var editing: ProfileEditorTarget?
    @State private var showsPaywall = false
    @FocusState private var focus: UUID?

    private var slotCount: Int {
        profiles.profiles.count + (profiles.canAdd ? 1 : 0)
    }

    /// How many cards fit on one row inside the 1400pt rail, capped by how many we actually have.
    private var columnsPerRow: Int {
        let maxFit = max(1, Int((1400 + Theme.Spacing.xl) / (ProfileCard.width + Theme.Spacing.xl)))
        return min(max(slotCount, 1), maxFit)
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(ProfileCard.width), spacing: Theme.Spacing.xl),
            count: columnsPerRow
        )
    }

    private var gridWidth: CGFloat {
        let n = columnsPerRow
        return CGFloat(n) * ProfileCard.width + CGFloat(max(n - 1, 0)) * Theme.Spacing.xl
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Text(isManaging ? "Gérer les profils" : "Qui regarde ?")
                .font(Theme.Typography.pageTitle).tracking(Theme.Typography.displayTracking)
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
                    .focused($focus, equals: profile.id)
                }
                if profiles.canAdd {
                    AddProfileCard { editing = .create }
                }
            }
            .frame(width: gridWidth)
            .frame(maxWidth: .infinity) // center the row as the count grows/shrinks
            .animation(Theme.Motion.fade, value: slotCount)
            .focusSection()
            HStack(spacing: Theme.Spacing.m) {
                Button(isManaging ? "Terminé" : "Gérer les profils", systemImage: isManaging ? "checkmark" : "pencil") {
                    isManaging.toggle()
                }
                .buttonStyle(PillButtonStyle(kind: isManaging ? .primary : .secondary))
                if !profiles.canAdd {
                    Button("Débloquer plus de profils", systemImage: "sparkles") {
                        showsPaywall = true
                    }
                    .buttonStyle(PillButtonStyle(kind: .primary))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Theme.Palette.canvas
                // The page takes the colour of the profile being looked at.
                RadialGradient(colors: [tint.opacity(0.30), .clear], center: .top, startRadius: 0, endRadius: 1100)
                    .animation(Theme.Motion.fade, value: tint)
            }
            .ignoresSafeArea()
        }
        .opensRailOnExit()
        .fullScreenCover(item: $editing) { target in
            ProfileEditorView(target: target)
        }
        .fullScreenCover(isPresented: $showsPaywall) {
            SubscriptionPaywallView()
        }
    }
}

extension ProfilesView {
    /// Colour of the focused profile, or of the active one while focus is elsewhere.
    fileprivate var tint: Color {
        let shown = profiles.profiles.first { $0.id == focus } ?? profiles.active
        return shown.avatar.color.color
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

    static let width: CGFloat = 260
    static let avatarSize: CGFloat = 220

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.m) {
                ProfileAvatarView(avatar: profile.avatar, size: Self.avatarSize)
                    // The active profile wears a white ring, set off from the disc.
                    .padding(10)
                    .overlay {
                        Circle().strokeBorder(Theme.Palette.focusRing, lineWidth: isActive ? 5 : 0)
                    }
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
            }
            .frame(width: Self.width)
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
            VStack(spacing: Theme.Spacing.m) {
                Circle()
                    .strokeBorder(Theme.Palette.textTertiary, style: StrokeStyle(lineWidth: 4, dash: [14, 10]))
                    .frame(width: ProfileCard.avatarSize, height: ProfileCard.avatarSize)
                    .padding(10)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 76, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                Text("Ajouter un profil")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(width: ProfileCard.width)
        }
        .buttonStyle(AvatarButtonStyle())
        .accessibilityLabel("Ajouter un profil")
    }
}
