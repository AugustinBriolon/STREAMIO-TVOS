import SwiftUI

public struct StreamsSheetView: View {
    public let type: String
    public let id: String
    public let mediaTitle: String
    
    @StateObject private var service = StremioService.shared
    @State private var streams: [StreamItem] = []
    @State private var isLoading = true
    @State private var selectedStream: StreamItem?
    
    @Environment(\.dismiss) private var dismiss
    
    public init(type: String, id: String, mediaTitle: String) {
        self.type = type
        self.id = id
        self.mediaTitle = mediaTitle
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sources disponibles")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text(mediaTitle)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                            Text("Fermer")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 54)
                .padding(.top, 40)
                
                if isLoading {
                    Spacer()
                    VStack(spacing: 18) {
                        ProgressView()
                            .scaleEffect(1.6)
                        Text("Recherche des flux en cours...")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        Text("Interrogation de vos addons configurés")
                            .font(.system(size: 15))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else if streams.isEmpty {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 56))
                            .foregroundColor(.yellow.opacity(0.8))
                        
                        Text("Aucune source trouvée")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                        
                        if service.configuredAddonURLs.isEmpty {
                            Text("Aucun addon de streaming n'est configuré.\nRendez-vous dans l'onglet Paramètres pour ajouter l'URL de votre addon (Torrentio, Lumio, etc.).")
                                .font(.system(size: 18))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 680)
                                .lineSpacing(4)
                        } else {
                            Text("Vos addons configurés n'ont retourné aucun flux actif pour ce contenu.")
                                .font(.system(size: 18))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 16) {
                            ForEach(streams) { stream in
                                StreamRowView(stream: stream) {
                                    selectedStream = stream
                                }
                            }
                        }
                        .padding(.horizontal, 54)
                        .padding(.bottom, 60)
                    }
                }
            }
        }
        .task {
            streams = await service.fetchStreams(type: type, id: id)
            isLoading = false
        }
        .fullScreenCover(item: $selectedStream) { stream in
            if let urlString = stream.url, let url = URL(string: urlString) {
                NativePlayerView(videoURL: url, title: mediaTitle)
                    .ignoresSafeArea()
            }
        }
    }
}

private struct StreamRowView: View {
    let stream: StreamItem
    let onSelect: () -> Void
    
    @FocusState private var isFocused: Bool
    
    private var resolutionColor: Color {
        let res = stream.resolution.uppercased()
        if res.contains("4K") {
            return Color(red: 0.45, green: 0.35, blue: 0.95) // Vibrant purple
        } else if res.contains("1080P") {
            return Color(red: 0.05, green: 0.55, blue: 0.95) // Cyan-Blue
        } else {
            return Color.gray.opacity(0.5)
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 20) {
                // Resolution Badge
                Text(stream.resolution)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(resolutionColor)
                    .clipShape(Capsule())
                
                // Stream Info
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        if stream.isDebrid {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 11))
                                Text("DEBRID")
                                    .font(.system(size: 11, weight: .heavy))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                        }
                        
                        Text(stream.providerName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                        
                        if let size = stream.sizeInfo {
                            Text("•")
                                .foregroundColor(.gray.opacity(0.5))
                            Text(size)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                        
                        if let seeds = stream.seedersInfo {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 10, weight: .bold))
                                Text(seeds)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            }
                            .foregroundColor(.green.opacity(0.85))
                        }
                        
                        if let audio = stream.audioBadge {
                            Text(audio)
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                    
                    Text(stream.parsedTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isFocused ? .black : .white)
                    .padding(14)
                    .background(isFocused ? Color.white : Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .padding(18)
            .background(isFocused ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isFocused ? Color.white.opacity(0.85) : Color.white.opacity(0.08),
                        lineWidth: isFocused ? 2.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isFocused)
    }
}