import SwiftUI

public struct HomeCatalogView: View {
    public let type: String
    public let title: String
    
    @StateObject private var service = StremioService.shared
    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var selectedItem: MediaItem?
    
    private let columns = [
        GridItem(.adaptive(minimum: 250), spacing: 32)
    ]
    
    public init(type: String, title: String) {
        self.type = type
        self.title = title
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    ProgressView("Chargement de \(title)...")
                        .scaleEffect(1.5)
                } else if items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "film")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("Aucun élément trouvé")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Text(title)
                                .font(.system(size: 38, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 48)
                                .padding(.top, 24)
                            
                            LazyVGrid(columns: columns, spacing: 40) {
                                ForEach(items) { item in
                                    MediaCardView(item: item) {
                                        selectedItem = item
                                    }
                                }
                            }
                            .padding(.horizontal, 48)
                            .padding(.bottom, 64)
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
            }
        }
        .task {
            items = await service.fetchCatalog(type: type)
            isLoading = false
        }
    }
}
