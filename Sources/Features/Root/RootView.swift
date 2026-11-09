import SwiftUI

/// Moves focus to the navigation rail; pages call it when Menu is pressed on their root screen.
/// A reference type, so the environment value never changes identity and pages are not re-rendered.
final class RailOpener {
    /// Shared default for views outside the root (previews, tests): does nothing.
    nonisolated(unsafe) static let inert = RailOpener()
    var open: () -> Void = {}
}

extension EnvironmentValues {
    @Entry var railOpener: RailOpener = .inert
}

extension View {
    /// Menu on a page's root screen opens the rail. Pushed screens do not use this, so Menu still goes back.
    func opensRailOnExit() -> some View {
        modifier(OpensRailOnExit())
    }
}

private struct OpensRailOnExit: ViewModifier {
    @Environment(\.railOpener) private var opener

    func body(content: Content) -> some View {
        content.onExitCommand { opener.open() }
    }
}

/// Icon rail navigation and the app-wide player presentation.
struct RootView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var selected: AppTab = .home
    /// Pages are created on first visit and then kept alive, so they keep their data and scroll position.
    @State private var visited: Set<AppTab> = [.home]
    @Environment(\.resetFocus) private var resetFocus
    @Namespace private var contentScope
    @State private var opener = RailOpener()
    /// False while a title page is pushed on Search: there Menu must go back, not open the rail.
    @State private var searchAtRoot = true
    /// The rail is focusable only while the user asks for it (Menu on a page). Left enabled it is the
    /// left-most focusable view: it wins the focus at launch (the page is still loading) and after
    /// a selection. Measured on device: `resetFocus` could not take the focus back from it.
    @State private var railEnabled = false
    @FocusState private var railFocus: AppTab?

    var body: some View {
        @Bindable var playback = playback
        ZStack(alignment: .leading) {
            Theme.Palette.canvas.ignoresSafeArea()
            pages.focusScope(contentScope)
            railScrim
            // Icons live in the screen margin (outside the safe area), left of every page's content,
            // so the rail never overlaps a card the focus engine could confuse with it.
            NavRail(selected: selected, focus: $railFocus, onSelect: select)
                .padding(.leading, Theme.Spacing.l)
                .ignoresSafeArea(edges: .leading)
                .disabled(!railEnabled)
        }
        .environment(\.railOpener, opener)
        // The system search keyboard cannot carry its own handler, so on Search's root screen Menu is
        // caught here. Everywhere else it is either a page handler (`opensRailOnExit`), a pushed screen
        // (Menu goes back: a root handler would swallow it, measured on device) or the rail itself
        // (Menu keeps its system meaning: leave the app).
        .onExitCommand(perform: railFocus == nil && selected == .search && searchAtRoot ? { opener.open() } : nil)
        .onAppear {
            opener.open = {
                railEnabled = true
                Task { @MainActor in
                    await Task.yield()
                    railFocus = selected
                }
            }
        }
        // Focus left the rail (right, or a selection): the page takes it back and the rail goes inert.
        .onChange(of: railFocus) { _, focused in
            if focused == nil { railEnabled = false }
        }
        .overlay {
            if playback.isResolving {
                StateView(kind: .loading("Recherche du meilleur flux…"))
                    .background(.black.opacity(0.75))
                    .ignoresSafeArea()
            }
        }
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
        case .home: HomeView(scope: nil)
        case .movies: HomeView(scope: .movie)
        case .series: HomeView(scope: .series)
        case .myList: MyListView()
        case .search: SearchView(atRoot: $searchAtRoot)
        case .settings: SettingsView(isActive: selected == .settings)
        }
    }

    /// Soft fade (not a panel) so names stay readable over bright artwork while the rail has focus.
    private var railScrim: some View {
        LinearGradient(colors: [.black.opacity(0.95), .black.opacity(0.85), .clear],
                       startPoint: .leading, endPoint: .trailing)
            .frame(width: 640)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(railFocus != nil ? 1 : 0)
            .animation(Theme.Motion.panel, value: railFocus != nil)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    private func select(_ tab: AppTab) {
        visited.insert(tab)
        withAnimation(Theme.Motion.fade) { selected = tab }
        // Selecting leaves the rail: disable it, then ask the focus engine to settle on the new page.
        // (Disabling alone leaves the focus on the dead rail until the next key press.)
        railEnabled = false
        railFocus = nil
        Task { @MainActor in
            await Task.yield()
            resetFocus(in: contentScope)
        }
    }
}
