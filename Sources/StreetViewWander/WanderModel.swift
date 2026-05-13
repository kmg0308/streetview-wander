import AppKit
import Foundation
import Security
import StreetViewWanderCore
import SwiftUI

@MainActor
final class WanderModel: ObservableObject {
    private enum DefaultsKey {
        static let browserAPIKey = "browserAPIKey"
        static let metadataAPIKey = "metadataAPIKey"
        static let hasBrowserAPIKey = "hasBrowserAPIKey"
        static let hasMetadataAPIKey = "hasMetadataAPIKey"
        static let selectedContinentId = "selectedContinentId"
        static let selectedCountryId = "selectedCountryId"
        static let metadataRequestLimit = "metadataRequestLimit"
        static let metadataRequestsUsed = "metadataRequestsUsed"
    }

    @Published private(set) var browserAPIKey: String
    @Published private(set) var metadataAPIKey: String
    @Published private var browserAPIKeyIsStored: Bool
    @Published private var metadataAPIKeyIsStored: Bool
    @Published var selectedContinentId: String {
        didSet {
            defaults.set(selectedContinentId, forKey: DefaultsKey.selectedContinentId)
            if !selectedContinentId.isEmpty,
               let country = locationOptions.countries.first(where: { $0.id == selectedCountryId }),
               country.continent != selectedContinentId {
                selectedCountryId = ""
            }
        }
    }
    @Published var selectedCountryId: String {
        didSet {
            defaults.set(selectedCountryId, forKey: DefaultsKey.selectedCountryId)
            if let country = locationOptions.countries.first(where: { $0.id == selectedCountryId }) {
                selectedContinentId = country.continent
            }
        }
    }
    @Published var metadataRequestLimit = 0 {
        didSet {
            if metadataRequestLimit < 0 {
                metadataRequestLimit = 0
            }
            defaults.set(metadataRequestLimit, forKey: DefaultsKey.metadataRequestLimit)
        }
    }

    @Published private(set) var panorama: Panorama?
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var locationOptions = LocationOptions.empty
    @Published private(set) var isLoading = false
    @Published private(set) var statusText = "Add API keys in Settings, then pick a random place."
    @Published private(set) var errorText: String?
    @Published private(set) var metadataRequestsUsed = 0 {
        didSet {
            defaults.set(metadataRequestsUsed, forKey: DefaultsKey.metadataRequestsUsed)
        }
    }
    @Published var activePanel: Panel = .none
    @Published var isSettingsPresented = false

    enum Panel {
        case none
        case details
        case history
        case scope
    }

    private let defaults: UserDefaults
    private let keychainStore: KeychainStore
    private let countryDataStore: CountryDataStore
    private let historyStore: HistoryStore
    private let panoramaFinder: PanoramaFinder

    init(
        defaults: UserDefaults = .standard,
        keychainStore: KeychainStore = KeychainStore(),
        countryDataStore: CountryDataStore = CountryDataStore(),
        historyStore: HistoryStore = HistoryStore()
    ) {
        self.defaults = defaults
        self.keychainStore = keychainStore
        self.countryDataStore = countryDataStore
        self.historyStore = historyStore
        self.panoramaFinder = PanoramaFinder(countryDataStore: countryDataStore)

        let legacyBrowserAPIKey = defaults.string(forKey: DefaultsKey.browserAPIKey)
        let legacyMetadataAPIKey = defaults.string(forKey: DefaultsKey.metadataAPIKey)
        self.browserAPIKey = legacyBrowserAPIKey ?? ""
        self.metadataAPIKey = legacyMetadataAPIKey ?? ""
        self.browserAPIKeyIsStored = false
        self.metadataAPIKeyIsStored = false
        self.selectedContinentId = defaults.string(forKey: DefaultsKey.selectedContinentId) ?? ""
        self.selectedCountryId = defaults.string(forKey: DefaultsKey.selectedCountryId) ?? ""
        self.metadataRequestLimit = max(0, defaults.integer(forKey: DefaultsKey.metadataRequestLimit))
        self.metadataRequestsUsed = max(0, defaults.integer(forKey: DefaultsKey.metadataRequestsUsed))

        let hasStoredBrowserAPIKey = storedSecretFlag(
            DefaultsKey.hasBrowserAPIKey,
            fallbackKey: DefaultsKey.browserAPIKey,
            legacyValue: legacyBrowserAPIKey
        )
        let hasStoredMetadataAPIKey = storedSecretFlag(
            DefaultsKey.hasMetadataAPIKey,
            fallbackKey: DefaultsKey.metadataAPIKey,
            legacyValue: legacyMetadataAPIKey
        )
        self.browserAPIKeyIsStored = hasStoredBrowserAPIKey || !(legacyBrowserAPIKey ?? "").isEmpty
        self.metadataAPIKeyIsStored = hasStoredMetadataAPIKey || !(legacyMetadataAPIKey ?? "").isEmpty

        migrateLegacySecret(legacyBrowserAPIKey, key: DefaultsKey.browserAPIKey, hasKeychainValue: hasStoredBrowserAPIKey)
        migrateLegacySecret(legacyMetadataAPIKey, key: DefaultsKey.metadataAPIKey, hasKeychainValue: hasStoredMetadataAPIKey)
        loadLocalData()
    }

    var hasBrowserAPIKey: Bool {
        browserAPIKeyIsStored || !browserAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasMetadataAPIKey: Bool {
        metadataAPIKeyIsStored || !metadataAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var metadataRequestsRemaining: Int? {
        guard metadataRequestLimit > 0 else {
            return nil
        }
        return max(metadataRequestLimit - metadataRequestsUsed, 0)
    }

    var selectedScopeLabel: String {
        if let country = locationOptions.countries.first(where: { $0.id == selectedCountryId }) {
            return country.label
        }
        if let continent = locationOptions.continents.first(where: { $0.id == selectedContinentId }) {
            return continent.label
        }
        return "Worldwide"
    }

    var filteredCountries: [CountryOption] {
        guard !selectedContinentId.isEmpty else {
            return locationOptions.countries
        }
        return locationOptions.countries.filter { $0.continent == selectedContinentId }
    }

    func loadLocalData() {
        do {
            locationOptions = try countryDataStore.locationOptions()
            history = try historyStore.load()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
            statusText = error.localizedDescription
        }
    }

    func clearScope() {
        selectedCountryId = ""
        selectedContinentId = ""
    }

    func revisit(_ entry: HistoryEntry) {
        loadStoredAPIKeysIfNeeded()
        panorama = entry.panorama
        statusText = "Revisited \(entry.areaLabel)."
        activePanel = .none
    }

    func randomPlace() {
        loadStoredAPIKeysIfNeeded()
        guard hasBrowserAPIKey else {
            isSettingsPresented = true
            errorText = "Add VITE_GOOGLE_MAPS_API_KEY in Settings."
            return
        }
        guard hasMetadataAPIKey else {
            isSettingsPresented = true
            errorText = "Add GOOGLE_STREET_VIEW_METADATA_API_KEY in Settings."
            return
        }
        if metadataRequestLimit > 0, metadataRequestsUsed >= metadataRequestLimit {
            errorText = PanoramaFinderError.metadataRequestLimitReached.localizedDescription
            statusText = errorText ?? "Metadata request limit reached."
            return
        }
        guard !isLoading else {
            return
        }

        isLoading = true
        errorText = nil
        statusText = "Finding a Street View panorama..."

        let selection = SearchSelection(
            continentId: selectedContinentId,
            countryId: selectedCountryId
        )
        let recentContinents = recentContinentLabels()
        let recentCountries = recentCountryLabels()
        let recentDensityTiers = recentSearchDensityTiers()
        let recentSceneKinds = recentSearchSceneKinds()
        let metadataAPIKey = metadataAPIKey
        let maxMetadataRequests = metadataRequestsRemaining

        Task {
            do {
                let next = try await panoramaFinder.findRandomPanorama(
                    metadataAPIKey: metadataAPIKey,
                    selection: selection,
                    recentContinents: recentContinents,
                    recentCountries: recentCountries,
                    recentDensityTiers: recentDensityTiers,
                    recentSceneKinds: recentSceneKinds,
                    maxMetadataRequests: maxMetadataRequests,
                    onMetadataRequest: { [weak self] in
                        await self?.recordMetadataRequest()
                    }
                )
                panorama = next
                history = try historyStore.append(next)
                let scene = next.sceneKind.map { "\($0.label) · " } ?? ""
                statusText = "\(next.areaLabel) · \(scene)\(next.attempts) metadata \(next.attempts == 1 ? "check" : "checks")"
                activePanel = .none
            } catch {
                errorText = error.localizedDescription
                statusText = error.localizedDescription
            }

            isLoading = false
        }
    }

    func resetMetadataRequestUsage() {
        metadataRequestsUsed = 0
    }

    func loadAPIKeysForEditing() {
        loadStoredAPIKeysIfNeeded()
    }

    private func recordMetadataRequest() {
        metadataRequestsUsed += 1
    }

    private func storedSecretFlag(_ flagKey: String, fallbackKey: String, legacyValue: String?) -> Bool {
        if defaults.object(forKey: flagKey) != nil {
            return defaults.bool(forKey: flagKey)
        }

        if let legacyValue,
           !legacyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(true, forKey: flagKey)
            return true
        }

        let hasKeychainValue = keychainStore.containsString(for: fallbackKey)
        defaults.set(hasKeychainValue, forKey: flagKey)
        return hasKeychainValue
    }

    func saveAPIKeys(browser: String, metadata: String) {
        let nextBrowserAPIKey = browser.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextMetadataAPIKey = metadata.trimmingCharacters(in: .whitespacesAndNewlines)
        var didChange = false

        if browserAPIKey != nextBrowserAPIKey {
            browserAPIKey = nextBrowserAPIKey
            persistSecret(nextBrowserAPIKey, key: DefaultsKey.browserAPIKey)
            browserAPIKeyIsStored = !nextBrowserAPIKey.isEmpty
            didChange = true
        }

        if metadataAPIKey != nextMetadataAPIKey {
            metadataAPIKey = nextMetadataAPIKey
            persistSecret(nextMetadataAPIKey, key: DefaultsKey.metadataAPIKey)
            metadataAPIKeyIsStored = !nextMetadataAPIKey.isEmpty
            didChange = true
        }

        if didChange {
            statusText = "Saved API keys."
            errorText = nil
        }
    }

    private func migrateLegacySecret(_ value: String?, key: String, hasKeychainValue: Bool) {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }

        if hasKeychainValue || keychainStore.setString(value, for: key) {
            defaults.removeObject(forKey: key)
            defaults.set(true, forKey: storedFlagKey(for: key))
        }
    }

    private func loadStoredAPIKeysIfNeeded() {
        if browserAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           browserAPIKeyIsStored {
            if let value = keychainStore.string(for: DefaultsKey.browserAPIKey) {
                browserAPIKey = value
            } else {
                browserAPIKeyIsStored = false
            }
        }

        if metadataAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           metadataAPIKeyIsStored {
            if let value = keychainStore.string(for: DefaultsKey.metadataAPIKey) {
                metadataAPIKey = value
            } else {
                metadataAPIKeyIsStored = false
            }
        }
    }

    private func persistSecret(_ value: String, key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            keychainStore.deleteString(for: key)
            defaults.removeObject(forKey: key)
            defaults.set(false, forKey: storedFlagKey(for: key))
            return
        }

        if keychainStore.setString(value, for: key) {
            defaults.removeObject(forKey: key)
            defaults.set(true, forKey: storedFlagKey(for: key))
        } else {
            defaults.set(value, forKey: key)
            defaults.set(true, forKey: storedFlagKey(for: key))
        }
    }

    private func storedFlagKey(for key: String) -> String {
        key == DefaultsKey.browserAPIKey ? DefaultsKey.hasBrowserAPIKey : DefaultsKey.hasMetadataAPIKey
    }

    private func recentContinentLabels() -> [String] {
        history.prefix(60).compactMap {
            $0.continentLabel ?? legacyContinentLabel(for: $0.areaLabel)
        }
    }

    private func recentCountryLabels() -> [String] {
        history.prefix(80).compactMap(\.countryLabel)
    }

    private func recentSearchDensityTiers() -> [SearchDensityTier] {
        history.prefix(60).map {
            SearchDensityTier.classify(
                requestedLocation: $0.requestedLocation,
                panoramaLocation: $0.location
            )
        }
    }

    private func recentSearchSceneKinds() -> [SearchSceneKind] {
        history.prefix(80).compactMap(\.sceneKind)
    }

    private func legacyContinentLabel(for areaLabel: String) -> String? {
        [
            "Alaska and Yukon": "North America",
            "Canada West": "North America",
            "Canada East": "North America",
            "United States": "North America",
            "Mexico": "North America",
            "Central America": "North America",
            "Caribbean": "North America",
            "Greenland and North Atlantic": "North America",
            "Iceland": "Europe",
            "British Isles": "Europe",
            "Iberia": "Europe",
            "Western Europe": "Europe",
            "Central Europe": "Europe",
            "Nordics": "Europe",
            "Baltics and Poland": "Europe",
            "Italy and Malta": "Europe",
            "Balkans": "Europe",
            "Eastern Europe": "Europe",
            "Greece and Cyprus": "Europe",
            "Turkey and Caucasus": "Asia",
            "Western Russia": "Europe",
            "Middle East": "Asia",
            "Central Asia": "Asia",
            "Northern Asia West": "Asia",
            "Northern Asia East": "Asia",
            "Mongolia and Northern China": "Asia",
            "Eastern China": "Asia",
            "South Asia": "Asia",
            "Mainland Southeast Asia": "Asia",
            "Maritime Southeast Asia": "Asia",
            "Japan and Korea": "Asia",
            "Taiwan Hong Kong and Macau": "Asia",
            "Australia and New Zealand": "Oceania",
            "Pacific Islands West": "Oceania",
            "Pacific Islands East": "Oceania",
            "Northern South America": "South America",
            "Brazil": "South America",
            "Andes": "South America",
            "Southern Cone": "South America",
            "North Africa": "Africa",
            "West Africa": "Africa",
            "East Africa": "Africa",
            "Southern Africa": "Africa",
            "Indian Ocean Islands": "Africa",
            "Antarctic Peninsula": "Antarctica",
            "Ross Island Antarctica": "Antarctica"
        ][areaLabel]
    }

    @discardableResult
    func importEnvFile() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = "Import .env"
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        do {
            let values = try EnvFile.parseFile(at: url)
            saveAPIKeys(
                browser: values["VITE_GOOGLE_MAPS_API_KEY"] ?? browserAPIKey,
                metadata: values["GOOGLE_STREET_VIEW_METADATA_API_KEY"] ?? metadataAPIKey
            )
            statusText = "Imported API keys from \(url.lastPathComponent)."
            errorText = nil
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }
}

struct KeychainStore {
    private let service = "com.kangmingyu.streetviewwander"

    func containsString(for account: String) -> Bool {
        var query = baseQuery(account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    func string(for account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func setString(_ value: String, for account: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }

        var query = baseQuery(account: account)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return true
        }
        guard status == errSecItemNotFound else {
            return false
        }

        query[kSecValueData as String] = data
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    func deleteString(for account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
