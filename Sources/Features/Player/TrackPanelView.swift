import SwiftUI

/// Everything in the player that can hold focus.
enum PlayerFocus: Hashable {
    case surface
    case audioButton, subtitleButton
    case audioTrack(Int32), subtitleTrack(Int32)
}

enum TrackColumn: Equatable {
    case audio, subtitles
}

/// Audio and subtitle picker. Plain buttons instead of a system `Menu`: on the Apple TV the system
/// popover ignored many remote clicks (measured: GameController saw every click, the Menu opened on
/// roughly one in ten) while plain buttons reacted every time.
struct TrackPanelView: View {
    let engine: VLCPlayerEngine
    let focus: FocusState<PlayerFocus?>.Binding

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.l) {
            column("Audio", symbol: "speaker.wave.2", tracks: engine.audioTracks, selected: engine.selectedAudioID,
                   allowsOff: false, focusValue: { .audioTrack($0) }) { engine.selectAudio($0) }
            column("Sous-titres", symbol: "captions.bubble", tracks: engine.subtitleTracks, selected: engine.selectedSubtitleID,
                   allowsOff: true, focusValue: { .subtitleTrack($0) }) { engine.selectSubtitle($0) }
        }
        .padding(Theme.Spacing.l)
        // Solid, not a blur material: blurring live video is expensive on the Apple TV HD.
        .background(Color.black.opacity(0.9), in: RoundedRectangle(cornerRadius: Theme.Radius.card * 2))
        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.card * 2).strokeBorder(Theme.Palette.surfaceRaised, lineWidth: 1) }
    }

    private func column(_ title: String, symbol: String, tracks: [MediaTrack], selected: Int32, allowsOff: Bool,
                        focusValue: @escaping (Int32) -> PlayerFocus, select: @escaping (Int32) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label(title, systemImage: symbol)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.horizontal, Theme.Spacing.s)
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.xs) {
                    if allowsOff {
                        row("Désactivés", isSelected: selected < 0, focusValue: focusValue(-1)) { select(-1) }
                    }
                    ForEach(tracks.filter { $0.id >= 0 }) { track in
                        row(TrackDisplay.title(track.name), isSelected: track.id == selected, focusValue: focusValue(track.id)) {
                            select(track.id)
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            .scrollClipDisabled()
        }
        .frame(width: 540)
        .frame(maxHeight: 420)
        .focusSection()
    }

    private func row(_ title: String, isSelected: Bool, focusValue: PlayerFocus, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Text(title).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if isSelected { Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)) }
            }
        }
        .buttonStyle(TrackRowStyle())
        .focused(focus, equals: focusValue)
    }
}

private struct TrackRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TrackRowBody(configuration: configuration)
    }
}

private struct TrackRowBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundStyle(isFocused ? Color.black : Theme.Palette.textPrimary)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isFocused ? Color.white : Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.button))
            .scaleEffect(isFocused ? 1.03 : 1)
            .animation(Theme.Motion.focus, value: isFocused)
    }
}
