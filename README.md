# StremioTV (Apple TV / tvOS)

Client Apple TV (tvOS) natif, moderne et ultra-léger pour Stremio développé en **SwiftUI**.

## 🌟 Fonctionnalités

- **Interface tvOS 100% native** : Adaptée à la télécommande Siri Remote avec mise en avant dynamique des éléments ciblés (`focus`).
- **Catalogue Cinemeta officiel** : Affiches, synopsis, notes IMDb, casting, films et séries populaires.
- **Support Séries complet** : Sélecteur de saisons et liste des épisodes avec vignettes.
- **Support Multi-Addons** : Interroge tous vos addons Stremio en parallèle (ex: *Lumio*, *Torrentio avec Real-Debrid*, etc.) et regroupe tous les flux disponibles triés par résolution (4K, 1080p, 720p).
- **Lecteur 4K natif** : Intégration de `AVPlayerViewController` pour une fluidité maximale, contrôle de lecture natif, pistes audio et sous-titres.
- **Serveur de configuration locale** : Intègre un mini-serveur web local sur le port `8080` permettant de gérer et coller vos URLs d'addons depuis Safari sur votre Mac ou iPhone en un clic.
- **Sauvegarde permanente** : Vos addons restent enregistrés localement dans le stockage sécurisé de l'Apple TV.

## 📁 Architecture du projet

```text
├── project.yml                     # Configuration XcodeGen
├── Sources/
│   ├── StremioTVApp.swift          # Point d'entrée de l'application
│   ├── Models/
│   │   └── StremioModels.swift     # Modèles de données (Catalog, Meta, Stream)
│   ├── Services/
│   │   ├── StremioService.swift    # Client réseau Cinemeta & Addons
│   │   └── ConfigServer.swift      # Serveur web local (NWListener) pour config Mac/iPhone
│   └── Views/
│       ├── RootView.swift          # TabView principale
│       ├── HomeCatalogView.swift   # Grille de films / séries
│       ├── MediaCardView.swift     # Carte d'affiche avec note IMDb
│       ├── MediaDetailView.swift   # Fiche détaillée (synopsis, saisons/épisodes)
│       ├── StreamsSheetView.swift  # Liste des flux vidéo triés par qualité
│       ├── NativePlayerView.swift  # Lecteur vidéo plein écran AVPlayer
│       ├── SearchCatalogView.swift # Recherche de films et séries
│       └── SettingsCatalogView.swift # Gestion des addons et statut du serveur local
```

## 🛠️ Compilation & Déploiement

### Prérequis
- macOS avec **Xcode 15+** ou **Xcode 16+**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Apple TV avec tvOS 17+ connectée sur le même réseau Wi-Fi

### Régénérer le projet Xcode
```bash
xcodegen generate
```

### Compiler pour l'Apple TV
```bash
xcodebuild -project StremioTV.xcodeproj -scheme StremioTV -destination "id=<UDID_DE_VOTRE_APPLE_TV>" -allowProvisioningUpdates build
```

### Installer sur l'Apple TV
```bash
xcrun devicectl device install app --device "<UDID_DE_VOTRE_APPLE_TV>" path/to/StremioTV.app
```
