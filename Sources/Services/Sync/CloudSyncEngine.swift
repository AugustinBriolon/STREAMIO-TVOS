import Foundation
import Observation

/// Moteur de synchronisation multi-écrans (Cloudflare Workers + D1).
/// Synchronise de façon bidirectionnelle les profils, "Ma liste", l'historique de lecture et les addons.
@MainActor
@Observable
public final class CloudSyncEngine {
    public private(set) var isSyncing: Bool = false
    public private(set) var lastSyncDate: Date? = nil
    public private(set) var syncError: String? = nil

    private let auth: AuthService
    private let profiles: ProfileStore
    private let library: LibraryStore
    private let addons: AddonStore
    private let defaults: UserDefaults

    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    /// The account refused this device's token (its session was signed out from the web).
    struct SessionRevoked: Error {}

    public init(
        auth: AuthService = .shared,
        profiles: ProfileStore,
        library: LibraryStore,
        addons: AddonStore,
        defaults: UserDefaults = AppGroup.defaults
    ) {
        self.auth = auth
        self.profiles = profiles
        self.library = library
        self.addons = addons
        self.defaults = defaults
        if let ts = defaults.object(forKey: "loge.lastSyncDate") as? Date
            ?? defaults.object(forKey: "stremiotv.lastSyncDate") as? Date {
            self.lastSyncDate = ts
        }
    }

    // MARK: - Synchronisation Complète (Pull puis Push)

    public func sync() async {
        guard auth.isAuthenticated, let token = auth.token else { return }
        guard !isSyncing else { return }

        isSyncing = true
        syncError = nil

        // Plan is not persisted locally (defaults to free until the Worker answers). Refresh first
        // or a cold launch always skips cloud pull — including addons added on the web.
        await auth.refreshDevices()
        profiles.plan = auth.plan
        addons.plan = auth.plan

        guard auth.limits.cloudSync else {
            isSyncing = false
            return
        }

        do {
            // Prefer the session token refreshDevices may have upgraded.
            let syncToken = auth.token ?? token
            try await pull(token: syncToken)
            if let pushToken = auth.token {
                try await push(token: pushToken)
                let now = Date()
                lastSyncDate = now
                defaults.set(now, forKey: "loge.lastSyncDate")
            }
            profiles.plan = auth.plan
            addons.plan = auth.plan
        } catch is SessionRevoked {
            // Signed out from another device: stop syncing, keep every local profile and history.
            auth.handleRevokedSession()
        } catch {
            syncError = error.localizedDescription
        }

        isSyncing = false
    }

    // MARK: - Pull (Téléchargement des données distantes)

    public func pull(token: String) async throws {
        guard let url = URL(string: "\(auth.apiBaseURL)/api/sync/pull") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        Self.applyDeviceHeaders(&req)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 401 { throw SessionRevoked() }
        guard status == 200 else {
            throw NSError(domain: "CloudSync", code: status, userInfo: [NSLocalizedDescriptionKey: "Échec du téléchargement (\(status))"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let upgraded = json["token"] as? String {
            auth.adoptUpgradedToken(upgraded)
        }
        if let planRaw = json["plan"] as? String, let plan = LogePlan(rawValue: planRaw) {
            profiles.plan = plan
            addons.plan = plan
        }

        let decoder = JSONDecoder()

        // 0. Profils supprimés ailleurs (ADR 0023)
        if let remoteDeleted = json["deletedProfiles"] as? [[String: Any]] {
            var deletions: [UUID: Date] = [:]
            for row in remoteDeleted {
                guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)) else { continue }
                deletions[id] = Self.date(fromMilliseconds: row["deleted_at_ms"]) ?? Date()
            }
            profiles.applyRemoteDeletions(deletions)
        }

        // 1. Profils distants
        if let remoteProfilesJson = json["profiles"] as? [[String: Any]] {
            var parsedProfiles: [Profile] = []
            for item in remoteProfilesJson {
                guard let idStr = item["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = item["name"] as? String,
                      let avatarJsonStr = item["avatar_json"] as? String,
                      let avatarData = avatarJsonStr.data(using: .utf8),
                      let avatar = try? decoder.decode(ProfileAvatar.self, from: avatarData) else {
                    continue
                }
                parsedProfiles.append(Profile(id: id, name: name, avatar: avatar))
            }
            // Joining a foyer with an empty guest "Profil 1" takes the account roster — never upload
            // that placeholder as a new household profile (merge + push looked like "auto-create").
            let localLibraryEmpty = library.myList.isEmpty && library.allProgress.isEmpty
            if !parsedProfiles.isEmpty, profiles.shouldAdoptAccountProfiles, localLibraryEmpty {
                profiles.adoptRemote(parsedProfiles)
                library.switchProfile(to: profiles.activeID)
                addons.switchProfile(to: profiles.activeID)
            } else if !parsedProfiles.isEmpty {
                profiles.mergeProfiles(parsedProfiles)
            }
        }

        // 2. Addons distants
        if let remoteAddons = json["addons"] as? [String] {
            for manifestUrl in remoteAddons {
                addons.add(manifestUrl)
            }
        }

        // 3. Ma liste distante + tombstones
        var remoteDeletedMyListByProfile: [UUID: [String: Date]] = [:]
        if let remoteDeletedMyList = json["deletedMyList"] as? [[String: Any]] {
            for row in remoteDeletedMyList {
                guard let profIdStr = row["profile_id"] as? String,
                      let profId = UUID(uuidString: profIdStr),
                      let itemId = row["item_id"] as? String,
                      let deletedAt = Self.date(fromMilliseconds: row["deleted_at_ms"]) else {
                    continue
                }
                remoteDeletedMyListByProfile[profId, default: [:]][itemId] = max(
                    remoteDeletedMyListByProfile[profId]?[itemId] ?? .distantPast,
                    deletedAt
                )
            }
        }

        if let remoteMyList = json["myList"] as? [[String: Any]] {
            var activeItems: [MediaItem] = []
            var activeTimestamps: [String: Date] = [:]
            var itemsByProfile: [UUID: [MediaItem]] = [:]
            var timestampsByProfile: [UUID: [String: Date]] = [:]

            for row in remoteMyList {
                guard let profIdStr = row["profile_id"] as? String,
                      let profId = UUID(uuidString: profIdStr),
                      let itemJsonStr = row["item_json"] as? String,
                      let itemData = itemJsonStr.data(using: .utf8),
                      let item = try? decoder.decode(MediaItem.self, from: itemData) else {
                    continue
                }
                let addedAt = Self.date(fromMilliseconds: row["updated_at_ms"]) ?? .distantPast

                if profId == library.profileID {
                    activeItems.append(item)
                    activeTimestamps[item.id] = addedAt
                } else {
                    itemsByProfile[profId, default: []].append(item)
                    timestampsByProfile[profId, default: [:]][item.id] = addedAt
                }
            }

            library.mergeRemote(
                items: activeItems,
                remoteTimestamps: activeTimestamps,
                remoteDeletions: remoteDeletedMyListByProfile[library.profileID] ?? [:]
            )

            let otherMyListProfiles = Set(itemsByProfile.keys).union(remoteDeletedMyListByProfile.keys)
                .filter { $0 != library.profileID }
            for profId in otherMyListProfiles {
                mergeInactiveProfileMyList(
                    profileID: profId,
                    remoteItems: itemsByProfile[profId] ?? [],
                    remoteTimestamps: timestampsByProfile[profId] ?? [:],
                    remoteDeletions: remoteDeletedMyListByProfile[profId] ?? [:],
                    decoder: decoder
                )
            }
        }

        // 4. Progression de lecture distante + tombstones
        var remoteDeletedProgressByProfile: [UUID: [String: Date]] = [:]
        if let remoteDeletedProgress = json["deletedProgress"] as? [[String: Any]] {
            for row in remoteDeletedProgress {
                guard let profIdStr = row["profile_id"] as? String,
                      let profId = UUID(uuidString: profIdStr),
                      let videoId = row["video_id"] as? String,
                      let deletedAt = Self.date(fromMilliseconds: row["deleted_at_ms"]) else {
                    continue
                }
                remoteDeletedProgressByProfile[profId, default: [:]][videoId] = max(
                    remoteDeletedProgressByProfile[profId]?[videoId] ?? .distantPast,
                    deletedAt
                )
            }
        }

        if let remoteProgress = json["progress"] as? [[String: Any]] {
            var activeProgress: [PlaybackProgress] = []
            var progressByProfile: [UUID: [PlaybackProgress]] = [:]

            for row in remoteProgress {
                guard let profIdStr = row["profile_id"] as? String,
                      let profId = UUID(uuidString: profIdStr),
                      let itemJsonStr = row["item_json"] as? String,
                      let itemData = itemJsonStr.data(using: .utf8),
                      let progressEntry = try? decoder.decode(PlaybackProgress.self, from: itemData) else {
                    continue
                }

                if profId == library.profileID {
                    activeProgress.append(progressEntry)
                } else {
                    progressByProfile[profId, default: []].append(progressEntry)
                }
            }

            library.mergeRemote(
                progress: activeProgress,
                remoteDeletions: remoteDeletedProgressByProfile[library.profileID] ?? [:]
            )

            let otherProgressProfiles = Set(progressByProfile.keys).union(remoteDeletedProgressByProfile.keys)
                .filter { $0 != library.profileID }
            for profId in otherProgressProfiles {
                mergeInactiveProfileProgress(
                    profileID: profId,
                    remoteEntries: progressByProfile[profId] ?? [],
                    remoteDeletions: remoteDeletedProgressByProfile[profId] ?? [:],
                    decoder: decoder
                )
            }
        }
    }

    // MARK: - Push (Envoi des données locales)

    public func push(token: String) async throws {
        guard let url = URL(string: "\(auth.apiBaseURL)/api/sync/push") else {
            throw URLError(.badURL)
        }

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // 1. Profils
        var profilesPayload: [[String: Any]] = []
        for (index, p) in profiles.profiles.enumerated() {
            // Lowercase: D1 UNIQUE(account_id, id) is case-sensitive; web already stores lowercase.
            profilesPayload.append([
                "id": p.id.uuidString.lowercased(),
                "name": p.name,
                "avatar": [
                    "color": p.avatar.color.rawValue,
                    "symbol": p.avatar.symbol.rawValue
                ],
                "sortOrder": index
            ])
        }

        // 2. Progression + suppressions de progression
        var progressPayload: [[String: Any]] = []
        var deletedProgressPayload: [[String: Any]] = []
        for p in profiles.profiles {
            let entries: [PlaybackProgress]
            let deletedMap: [String: Date]
            if p.id == library.profileID {
                entries = library.allProgress
                deletedMap = library.deletedProgressEntries
            } else {
                entries = defaults.data(forKey: StorageKey.progress(p.id))
                    .flatMap { try? decoder.decode([PlaybackProgress].self, from: $0) } ?? []
                deletedMap = defaults.data(forKey: StorageKey.deletedProgress(p.id))
                    .flatMap { try? decoder.decode([String: Date].self, from: $0) } ?? [:]
            }

            for entry in entries {
                if let entryData = try? encoder.encode(entry),
                   let entryJsonStr = String(data: entryData, encoding: .utf8) {
                    progressPayload.append([
                        "profileId": p.id.uuidString.lowercased(),
                        "videoId": entry.id,
                        "item": entryJsonStr,
                        "position": entry.position,
                        "duration": entry.duration,
                        "updatedAtMs": Self.milliseconds(from: entry.updatedAt)
                    ])
                }
            }

            for (videoId, deletedAt) in deletedMap {
                deletedProgressPayload.append([
                    "profileId": p.id.uuidString.lowercased(),
                    "videoId": videoId,
                    "deletedAtMs": Self.milliseconds(from: deletedAt)
                ])
            }
        }

        // 3. Ma liste + suppressions de Ma liste
        var myListPayload: [[String: Any]] = []
        var deletedMyListPayload: [[String: Any]] = []
        for p in profiles.profiles {
            let items: [MediaItem]
            let timestamps: [String: Date]
            let deletedMap: [String: Date]
            if p.id == library.profileID {
                items = library.myList
                timestamps = [:]
                deletedMap = library.deletedMyListEntries
            } else {
                items = defaults.data(forKey: StorageKey.myList(p.id))
                    .flatMap { try? decoder.decode([MediaItem].self, from: $0) } ?? []
                timestamps = defaults.data(forKey: StorageKey.myListTimestamps(p.id))
                    .flatMap { try? decoder.decode([String: Date].self, from: $0) } ?? [:]
                deletedMap = defaults.data(forKey: StorageKey.deletedMyList(p.id))
                    .flatMap { try? decoder.decode([String: Date].self, from: $0) } ?? [:]
            }

            for item in items {
                if let itemData = try? encoder.encode(item),
                   let itemJsonStr = String(data: itemData, encoding: .utf8) {
                    let addedAt = (p.id == library.profileID ? library.myListAddedAt(for: item.id) : timestamps[item.id])
                        ?? Date(timeIntervalSince1970: 0)
                    myListPayload.append([
                        "profileId": p.id.uuidString.lowercased(),
                        "itemId": item.id,
                        "item": itemJsonStr,
                        "addedAtMs": Self.milliseconds(from: addedAt)
                    ])
                }
            }

            for (itemId, deletedAt) in deletedMap {
                deletedMyListPayload.append([
                    "profileId": p.id.uuidString.lowercased(),
                    "itemId": itemId,
                    "deletedAtMs": Self.milliseconds(from: deletedAt)
                ])
            }
        }

        // 4. Addons
        let addonsPayload = addons.urls

        // 5. Profils supprimés
        let reportedDeletions = profiles.deletedProfiles
        let deletedProfilesPayload: [[String: Any]] = reportedDeletions.map { id, date in
            ["id": id.uuidString.lowercased(), "deletedAtMs": Self.milliseconds(from: date)]
        }

        let body: [String: Any] = [
            "profiles": profilesPayload,
            "deletedProfiles": deletedProfilesPayload,
            "progress": progressPayload,
            "deletedProgress": deletedProgressPayload,
            "myList": myListPayload,
            "deletedMyList": deletedMyListPayload,
            "addons": addonsPayload
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        Self.applyDeviceHeaders(&req)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 401 { throw SessionRevoked() }
        guard status == 200 else {
            throw NSError(domain: "CloudSync", code: status, userInfo: [NSLocalizedDescriptionKey: "Échec de l'envoi (\(status))"])
        }
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let upgraded = json["token"] as? String {
            auth.adoptUpgradedToken(upgraded)
        }
        profiles.clearReportedDeletions(Set(reportedDeletions.keys))
    }

    /// Déclenche un envoi après délai d'inactivité (debounced).
    /// Push only: a full sync would pull first and overwrite the local edit we are trying to upload.
    public func triggerPushDebounced() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled, let token = self.auth.token else { return }
            do {
                try await self.push(token: token)
            } catch is SessionRevoked {
                self.auth.handleRevokedSession()
            } catch {
                self.syncError = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    private static func applyDeviceHeaders(_ request: inout URLRequest) {
        let device = DeviceIdentity.current
        request.setValue(device.name, forHTTPHeaderField: "X-Device-Name")
        request.setValue(device.model, forHTTPHeaderField: "X-Device-Model")
        request.setValue("tv", forHTTPHeaderField: "X-Client-Kind")
    }

    private static func date(fromMilliseconds value: Any?) -> Date? {
        guard let num = value as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: num.doubleValue / 1000.0)
    }

    private static func milliseconds(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000.0).rounded())
    }

    private func mergeInactiveProfileMyList(
        profileID: UUID,
        remoteItems: [MediaItem],
        remoteTimestamps: [String: Date],
        remoteDeletions: [String: Date],
        decoder: JSONDecoder
    ) {
        let listKey = StorageKey.myList(profileID)
        let tsKey = StorageKey.myListTimestamps(profileID)
        let delKey = StorageKey.deletedMyList(profileID)

        var list = defaults.data(forKey: listKey).flatMap { try? decoder.decode([MediaItem].self, from: $0) } ?? []
        var timestamps = defaults.data(forKey: tsKey).flatMap { try? decoder.decode([String: Date].self, from: $0) } ?? [:]
        var deletions = defaults.data(forKey: delKey).flatMap { try? decoder.decode([String: Date].self, from: $0) } ?? [:]

        for (id, remoteDel) in remoteDeletions {
            if remoteDel > (deletions[id] ?? .distantPast) {
                deletions[id] = remoteDel
            }
            if remoteDel > (timestamps[id] ?? .distantPast) {
                list.removeAll { $0.id == id }
                timestamps.removeValue(forKey: id)
            }
        }

        for item in remoteItems {
            let remoteAdded = remoteTimestamps[item.id] ?? .distantPast
            if let localDel = deletions[item.id] {
                if remoteAdded > localDel {
                    deletions.removeValue(forKey: item.id)
                } else {
                    continue
                }
            }
            if !list.contains(where: { $0.id == item.id }) {
                list.append(item)
                if remoteAdded > (timestamps[item.id] ?? .distantPast) {
                    timestamps[item.id] = remoteAdded
                }
            }
        }

        let encoder = JSONEncoder()
        if let d = try? encoder.encode(list) { defaults.set(d, forKey: listKey) }
        if let d = try? encoder.encode(timestamps) { defaults.set(d, forKey: tsKey) }
        if let d = try? encoder.encode(deletions) { defaults.set(d, forKey: delKey) }
    }

    private func mergeInactiveProfileProgress(
        profileID: UUID,
        remoteEntries: [PlaybackProgress],
        remoteDeletions: [String: Date],
        decoder: JSONDecoder
    ) {
        let progKey = StorageKey.progress(profileID)
        let delKey = StorageKey.deletedProgress(profileID)

        let existing = defaults.data(forKey: progKey).flatMap { try? decoder.decode([PlaybackProgress].self, from: $0) } ?? []
        var dict = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { $0.updatedAt > $1.updatedAt ? $0 : $1 })
        var deletions = defaults.data(forKey: delKey).flatMap { try? decoder.decode([String: Date].self, from: $0) } ?? [:]

        for (videoID, remoteDel) in remoteDeletions {
            if remoteDel > (deletions[videoID] ?? .distantPast) {
                deletions[videoID] = remoteDel
            }
            if let cur = dict[videoID], !cur.isFinished, remoteDel > cur.updatedAt {
                dict.removeValue(forKey: videoID)
            }
        }

        for entry in remoteEntries {
            if let localDel = deletions[entry.id] {
                if entry.updatedAt > localDel {
                    deletions.removeValue(forKey: entry.id)
                } else {
                    continue
                }
            }
            if let cur = dict[entry.id] {
                if entry.updatedAt > cur.updatedAt { dict[entry.id] = entry }
            } else {
                dict[entry.id] = entry
            }
        }

        let encoder = JSONEncoder()
        if let d = try? encoder.encode(Array(dict.values)) { defaults.set(d, forKey: progKey) }
        if let d = try? encoder.encode(deletions) { defaults.set(d, forKey: delKey) }
    }

    // MARK: - Logout

    /// Intentional sign-out / account deletion: drop synced household data so the next login starts clean.
    /// Remote revoke keeps local data on purpose — do not call this from `handleRevokedSession`.
    public func clearLocalHousehold() {
        debounceTask?.cancel()
        debounceTask = nil
        isSyncing = false
        syncError = nil
        lastSyncDate = nil
        defaults.removeObject(forKey: "loge.lastSyncDate")
        defaults.removeObject(forKey: "stremiotv.lastSyncDate")

        profiles.resetToGuest()
        library.adoptProfile(profiles.activeID)
        addons.resetToDefaults()
    }
}
