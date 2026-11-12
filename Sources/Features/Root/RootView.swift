import SwiftUI

/// Moves focus to the navigation rail; pages call it when Menu is pressed on their root screen.
/// A reference type, so the environment value never changes identity and pages are not re-rendered.
final class RailOpener {
    /// Shared default for views outside the root (previews, tests): does nothing.
    nonisolated(unsafe) static let inert = RailOpener()
    var open: () -> Void = {}
}

/// Suppresses the nav rail as a focus candidate while Settings detail (not the rail) owns focus.
/// `railFocused` must win: blocking the rail while it holds focus disables every icon and the enter-snap
/// then pins focus on `selected` (felt as “stuck on Accueil”).
@Observable final class RailBlocker {
    nonisolated(unsafe) static let inert = RailBlocker()
    var detailBlocksRail = false
    var railFocused = false
    var isBlocked: Bool { detailBlocksRail && !railFocused }
}

extension EnvironmentValues {
    @Entry var railOpener: RailOpener = .inert
    @Entry var railBlocker: RailBlocker = .inert
}

extension View {
    /// Menu on a page's root screen opens the rail. Disable while a destination is pushed so Menu pops.
    func opensRailOnExit(when enabled: Bool = true) -> some View {
        modifier(OpensRailOnExit(enabled: enabled))
    }
}

private struct OpensRailOnExit: ViewModifier {
    var enabled: Bool = true
    @Environment(\.railOpener) private var opener

    func body(content: Content) -> some View {
        content.onExitCommand(perform: enabled ? { opener.open() } : nil)
    }
}

/// Icon rail navigation and the app-wide player presentation.
struct RootView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(ProfileStore.self) private var profiles
    @Environment(LibraryStore.self) private var library
    @Environment(AddonStore.self) private var addons
    @Environment(CloudSyncEngine.self) private var syncEngine
    @Environment(AuthService.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: AppTab = .home
    /// Pages are created on first visit and then kept alive, so they keep their data and scroll position.
    @State private var visited: Set<AppTab> = [.home]
    @State private var router = NavigationRouter()
    @Environment(\.resetFocus) private var resetFocus
    @Namespace private var contentScope
    @State private var opener = RailOpener()
    /// A title the Top Shelf asked to show: the home page pushes its detail page.
    @State private var linkedTitle: MediaItem?
    /// The rail is the left-most focusable view: enabled from the start it wins the focus at launch (the page
    /// is still loading) and after a selection, and `resetFocus` cannot take it back (measured on device).
    /// So it becomes focusable once a page element has held focus (`railReady`) and is switched off between
    /// a selection and the next page focus (`railSuppressed`). From then on moving left from any card reaches it.
    @State private var railReady = false
    @State private var railSuppressed = false
    @State private var railBlocker = RailBlocker()
    @State private var lastRailTab: AppTab?
    private var railEnabled: Bool { railReady && !railSuppressed && !railBlocker.isBlocked }
    @FocusState private var railFocus: AppTab?

    var body: some View {
        @Bindable var playback = playback
        ZStack(alignment: .leading) {
            Theme.Palette.canvas.ignoresSafeArea()
            pages.focusScope(contentScope)
                .fullScreenCover(isPresented: Binding(
                    get: { auth.showsWelcome },
                    // Menu on the welcome screen means "not now", like "Continuer sans compte".
                    set: { if !$0 && !auth.isAuthenticated { auth.dismissWelcome() } }
                )) {
                    WelcomeView()
                }
            restingRailScrim
            railScrim
            // Icons live in the screen margin (outside the safe area), left of every page's content,
            // so the rail never overlaps a card the focus engine could confuse with it.
            NavRail(
                selected: selected,
                profileName: profiles.active.name,
                profileAvatar: profiles.active.avatar,
                isAtRoot: { router.isAtRoot(for: $0) },
                focus: $railFocus,
                onSelect: select,
                onExitToPage: returnFocusToPage
            )
                .padding(.leading, Theme.Spacing.l)
                .ignoresSafeArea(edges: .leading)
                .disabled(!railEnabled)
                // Menu inside the rail closes it (the system default would leave the app).
                .onExitCommand(perform: returnFocusToPage)
        }
        .environment(\.railOpener, opener)
        .environment(\.railBlocker, railBlocker)
        // Each profile has its own list and progress: follow the active one.
        .onChange(of: profiles.activeID) { _, id in
            library.switchProfile(to: id)
            addons.switchProfile(to: id)
            TopShelfRefresher.refresh()
            syncEngine.triggerPushDebounced()
        }
        // The Top Shelf shows the profile's "Reprendre la lecture": refresh it when a playback ends.
        .onChange(of: playback.session == nil) { _, ended in
            if ended {
                TopShelfRefresher.refresh()
                syncEngine.triggerPushDebounced()
            }
        }
        .onChange(of: library.syncRevision) {
            TopShelfRefresher.refresh()
            syncEngine.triggerPushDebounced()
        }
        // Creating, renaming or deleting a profile must reach the account too (ADR 0023).
        .onChange(of: profiles.profiles) {
            syncEngine.triggerPushDebounced()
        }
        // Auth cleared (revoked session / expired token): tear down playback so Welcome cannot
        // sit on top of a still-audible player, and a later play cannot stack a second VLC instance.
        .onChange(of: auth.isAuthenticated) { _, signedIn in
            if !signedIn { playback.close() }
        }
        // The account's profiles replaced this device's first-launch profile: ask who is watching.
        .onChange(of: profiles.adoptionCount) {
            select(.profiles)
        }
        .onOpenURL(perform: open)
        // The system search keyboard cannot carry its own handler, so on Search's root screen Menu is
        // caught here. Everywhere else it is either a page handler (`opensRailOnExit`), a pushed screen
        // (Menu goes back: a root handler would swallow it, measured on device) or the rail itself
        // (Menu keeps its system meaning: leave the app).
        .onExitCommand(perform: railFocus == nil && selected == .search && router.isAtRoot(for: .search) ? { opener.open() } : nil)
        .onAppear {
            opener.open = {
                railReady = true
                railSuppressed = false
                railBlocker.detailBlocksRail = false
                Task { @MainActor in
                    await Task.yield()
                    railFocus = selected
                }
            }
        }
        // Entering the rail from a page lands on the current destination, not on whichever icon is nearest in height.
        .onChange(of: railFocus) { old, new in
            railBlocker.railFocused = (new != nil)
            if new != nil { railBlocker.detailBlocksRail = false }
            if let new { lastRailTab = new }
            guard old == nil, let new, new != selected else { return }
            railFocus = selected
            lastRailTab = selected
        }
        .onReceive(NotificationCenter.default.publisher(for: UIFocusSystem.didUpdateNotification)) { note in
            let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext
            guard let context else { return }

            // A page element took the focus: the rail may now be reached by moving left.
            guard railFocus == nil, context.nextFocusedItem != nil else { return }
            railReady = true
            railSuppressed = false
            lastRailTab = nil
        }
        .overlay {
            if let item = playback.resolvingItem {
                ResolvingView(item: item)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.fade, value: playback.isResolving)
        .fullScreenCover(isPresented: Binding(
            get: { playback.session != nil },
            set: { if !$0 { playback.close() } }
        )) {
            if let session = playback.session {
                PlayerView(session: session, playback: playback).ignoresSafeArea()
            }
        }
        .alert("Lecture impossible", isPresented: Binding(
            get: { playback.errorMessage != nil },
            set: { if !$0 { playback.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playback.errorMessage ?? "")
        }
    }

    private var pages: some View {
        ZStack {
            ForEach(AppTab.allCases, id: \.self) { tab in
                if visited.contains(tab) {
                    page(for: tab)
                        .transition(.identity)
                        .opacity(tab == selected ? 1 : 0)
                        .zIndex(tab == selected ? 1 : 0)
                        // Hidden pages must not hold focus or be read by VoiceOver.
                        .disabled(tab != selected)
                        .accessibilityHidden(tab != selected)
                }
            }
        }
    }

    @ViewBuilder
    private func page(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView(scope: nil, path: router.path(for: .home), linkedTitle: $linkedTitle)
        case .movies: HomeView(scope: .movie, path: router.path(for: .movies))
        case .series: HomeView(scope: .series, path: router.path(for: .series))
        case .myList: MyListView(path: router.path(for: .myList))
        case .search: SearchView(path: router.path(for: .search), atRoot: Binding(
            get: { router.isAtRoot(for: .search) },
            set: { _ in }
        ))
        case .settings: SettingsView(isActive: selected == .settings)
        case .profiles: ProfilesView(onSwitched: { select(.home) })
        }
    }

    /// Subtle resting canvas gradient anchoring the collapsed rail before horizontal shelf fades meet it.
    private var restingRailScrim: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.Palette.canvas.opacity(0.94), location: 0.0),
                .init(color: Theme.Palette.canvas.opacity(0.82), location: 0.58),
                .init(color: Theme.Palette.canvas.opacity(0.38), location: 0.80),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 124)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Soft progressive fade so titles stay crisp over bright hero artwork while the rail is expanded.
    private var railScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.92), location: 0.0),
                .init(color: .black.opacity(0.85), location: 0.30),
                .init(color: .black.opacity(0.50), location: 0.65),
                .init(color: .black.opacity(0.15), location: 0.85),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 680)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(railFocus != nil ? 1 : 0)
        .animation(reduceMotion ? nil : Theme.Motion.panel, value: railFocus != nil)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Top Shelf links (ADR 0016): the Play button resumes or plays, selecting an item shows its page.
    private func open(_ url: URL) {
        switch TopShelfLink(url: url) {
        case .resume(let id):
            guard let entry = library.progress(for: id) else { return }
            Task { await playback.play(item: entry.item, video: entry.video) }
        case .play(let id):
            guard let item = library.item(withID: id) else { return }
            Task { await playback.play(item: item) }
        case .details(let id):
            guard let item = library.item(withID: id) else { return }
            playback.close()
            if selected != .home { select(.home) }
            router.homePath = NavigationPath([item])
        case nil:
            break
        }
    }

    private func select(_ tab: AppTab) {
        if selected == tab {
            // Contrat Apple HIG Pop to Root: re-sélectionner l'onglet actif dépile immédiatement la navigation.
            if !router.isAtRoot(for: tab) {
                withAnimation(Theme.Motion.fade) {
                    router.popToRoot(for: tab)
                }
                returnFocusToPage()
                return
            }
        }
        visited.insert(tab)
        withAnimation(Theme.Motion.fade) { selected = tab }
        returnFocusToPage()
    }

    /// Leaves the rail: disable it, then ask the focus engine to settle on the page.
    /// (Disabling alone leaves the focus on the dead rail until the next key press.)
    private func returnFocusToPage() {
        railSuppressed = true
        railFocus = nil
        Task { @MainActor in
            await Task.yield()
            resetFocus(in: contentScope)
            // A page with nothing focusable (still loading) must not keep the rail off forever.
            try? await Task.sleep(for: .seconds(2))
            railSuppressed = false
        }
    }
}
