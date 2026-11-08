import SwiftUI

public struct SettingsCatalogView: View {
    @StateObject private var service = StremioService.shared
    @StateObject private var configServer = ConfigServer.shared
    
    @State private var inputURL = ""
    @State private var showSavedAlert = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    Text("Paramètres & Addons")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 24)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "iphone.and.arrow.forward")
                                .font(.system(size: 28))
                                .foregroundColor(.blue)
                            Text("Ajouter / Gérer depuis votre Mac ou Téléphone")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Text("Pour coller ou supprimer des addons facilement sans télécommande, ouvrez cette page web dans Safari :")
                            .font(.system(size: 18))
                            .foregroundColor(.gray)
                        
                        if configServer.isRunning && !configServer.serverURLString.isEmpty {
                            Text(configServer.serverURLString)
                                .font(.system(size: 28, weight: .heavy, design: .monospaced))
                                .foregroundColor(.yellow)
                                .padding(16)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                        } else {
                            ProgressView("Démarrage du serveur local...")
                        }
                    }
                    .padding(32)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(16)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Addons actifs (\(service.configuredAddonURLs.count))")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        if service.configuredAddonURLs.isEmpty {
                            Text("Aucun addon configuré. Les flux de lecture ne seront pas disponibles.")
                                .font(.system(size: 18))
                                .foregroundColor(.gray)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(service.configuredAddonURLs, id: \.self) { addon in
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text(addon)
                                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Spacer()
                                        Button("Supprimer") {
                                            service.removeAddonURL(addon)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.red)
                                    }
                                    .padding(14)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(10)
                                }
                            }
                        }
                    }
                    .padding(32)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(16)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Ajouter manuellement à la télécommande")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        TextField("https://...", text: $inputURL)
                            .font(.system(size: 20))
                            .padding(16)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                        
                        Button("Ajouter l'Addon") {
                            service.addAddonURL(inputURL)
                            inputURL = ""
                            showSavedAlert = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(32)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(16)
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 64)
            }
        }
        .onAppear {
            configServer.start()
        }
        .alert("Ajouté !", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("L'addon a été enregistré sur votre Apple TV.")
        }
    }
}
