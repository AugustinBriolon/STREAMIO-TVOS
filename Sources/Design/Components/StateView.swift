import SwiftUI

/// Loading, empty and error placeholders shared by every screen.
struct StateView: View {
    enum Kind {
        case loading(String)
        case empty(symbol: String, title: String, message: String)
        case error(String, retry: () -> Void)
    }

    let kind: Kind

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            switch kind {
            case .loading(let message):
                ProgressView()
                Text(message).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textSecondary)
            case .empty(let symbol, let title, let message):
                Image(systemName: symbol).font(.system(size: 64)).foregroundStyle(Theme.Palette.textTertiary)
                Text(title).font(Theme.Typography.rowTitle).foregroundStyle(Theme.Palette.textPrimary)
                Text(message).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 760)
            case .error(let message, let retry):
                Image(systemName: "wifi.exclamationmark").font(.system(size: 64)).foregroundStyle(Theme.Palette.textTertiary)
                Text("Une erreur est survenue").font(Theme.Typography.rowTitle).foregroundStyle(Theme.Palette.textPrimary)
                Text(message).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 760)
                Button("Réessayer", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(PillButtonStyle(kind: .primary))
                    .padding(.top, Theme.Spacing.m)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
