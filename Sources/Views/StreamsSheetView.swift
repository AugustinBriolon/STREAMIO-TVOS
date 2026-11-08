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
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Flux disponibles")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                        Text(mediaTitle)
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Button("Fermer") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 48)
                .padding(.top, 36)
                
                if isLoading {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView("Recherche des sources...")
                            .scaleEffect(1.5)
                        Spacer()
                    }
                    Spacer()
                } else if streams.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.yellow)
                        Text("Aucun flux trouvé")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        if service.configuredAddonURLs.isEmpty {
                            Text("Veuillez configurer l'URL de votre addon (Lumio, Torrentio...) dans l'onglet Paramètres.")
                                .font(.system(size: 18))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 600)
                        } else {
                            Text("Votre addon n'a pas retourné de source pour ce titre.")
                                .font(.system(size: 18))
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(streams) { stream in
                                Button {
                                    selectedStream = stream
                                } label: {
                                    HStack(spacing: 20) {
                                        Text(stream.resolution)
                                            .font(.system(size: 16, weight: .heavy))
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.yellow)
                                            .cornerRadius(8)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            if let name = stream.name, !name.isEmpty {
                                                Text(name)
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundColor(.white.opacity(0.8))
                                            }
                                            Text(stream.parsedTitle)
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(.white)
                                                .lineLimit(2)
                                        }
                                        Spacer()
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.white)
                                    }
                                    .padding(20)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.card)
                            }
                        }
                        .padding(.horizontal, 48)
                        .padding(.bottom, 48)
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
