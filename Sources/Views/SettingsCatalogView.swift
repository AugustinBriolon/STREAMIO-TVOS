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
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    Text("Paramètres & Addons")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.top, 24)
                    
                    // Web Manager Card
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            Image(systemName: "globe.badge.chevron.backward")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.blue)
                            Text("Gestion rapide depuis Mac / iPhone")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        
                        Text("Pour coller vos liens d'addons (Lumio, Torrentio, etc.) sans taper à la télécommande, ouvrez Safari sur votre téléphone ou ordinateur connecté au même Wi-Fi :")
                            .font(.system(size: 17))
                            .foregroundColor(.white.opacity(0.8))
                            .lineSpacing(4)
                        
                        if configServer.isRunning && !configServer.serverURLString.isEmpty {
                            HStack {
                                Image(systemName: "link")
                                    .foregroundColor(.yellow)
                                    .font(.system(size: 20))
                                Text(configServer.serverURLString)
                                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                                    .foregroundColor(.yellow)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(Color.yellow.opacity(0.12))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.3), lineWidth: 1))
                        } else {
                            ProgressView("Démarrage du portail de configuration...")
                        }
                    }
                    .padding(32)
                    .background(.ultraThinMaterial)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    
                    // Active Addons List
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("Addons actifs")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(service.configuredAddonURLs.count) configuré(s)")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                        }
                        
                        if service.configuredAddonURLs.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "puzzlepiece")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray.opacity(0.5))
                                Text("Aucun addon configuré pour l'instant.")
                                    .font(.system(size: 18))
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(service.configuredAddonURLs, id: \.self) { addon in
                                    HStack(spacing: 16) {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundColor(.green)
                                            .font(.system(size: 20))
                                        
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
                                    .padding(16)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }
                    .padding(32)
                    .background(.ultraThinMaterial)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    
                    // Manual Input
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Ajouter manuellement une URL")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 16) {
                            TextField("https://...", text: $inputURL)
                                .font(.system(size: 20))
                                .padding(16)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(12)
                                .foregroundColor(.white)
                            
                            Button("Ajouter") {
                                if !inputURL.isEmpty {
                                    service.addAddonURL(inputURL)
                                    inputURL = ""
                                    showSavedAlert = true
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                    }
                    .padding(32)
                    .background(.ultraThinMaterial)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    
                    // App Info
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Text("StremioTV pour Apple TV")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                            Text("Version 1.0 (SwiftUI natif)")
                                .font(.system(size: 14))
                                .foregroundColor(.gray.opacity(0.6))
                        }
                        Spacer()
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 60)
                }
                .padding(.horizontal, 54)
            }
        }
        .alert("Addon ajouté", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("L'addon a été enregistré avec succès et sera interrogé pour les flux vidéo.")
        }
    }
}