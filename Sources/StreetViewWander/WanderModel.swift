import AppKit
import Foundation
import StreetViewWanderCore
import SwiftUI

@MainActor
final class WanderModel: ObservableObject {
    private enum DefaultsKey {
        static let browserAPIKey = "browserAPIKey"
        static let metadataAPIKey = "metadataAPIKey"
        static let selectedContinentId = "selectedContinentId"
        static let selectedCountryId = "selectedCountryId"
    }

    @Published var browserAPIKey: String {
        didSet { defaults.set(browserAPIKey, forKey: DefaultsKey.browserAPIKey) }
    }
    @Published var metadataAPIKey: String {
        didSet { defaults.set(metadataAPIKey, forKey: DefaultsKey.metadataAPIKey) }
    }
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

    @Published private(set) var panorama: Panorama?
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var locationOptions = LocationOptions.empty
    @Published private(set) var isLoading = false
    @Published private(set) var statusText = "Add API keys in Settings, then pick a random place."
    @Published private(set) var errorText: String?
    @Published var activePanel: Panel = .none
    @Published var isSettingsPresented = false

    enum Panel {
        case none
        case details
        case history
        case scope
    }

    private let defaults: UserDefaults
    private let countryDataStore: CountryDataStore
    private let historyStore: HistoryStore
    private let panoramaFinder: PanoramaFinder

    init(
        defaults: UserDefaults = .standard,
        countryDataStore: CountryDataStore = CountryDataStore(),
        historyStore: HistoryStore = HistoryStore()
    ) {
        self.defaults = defaults
        self.countryDataStore = countryDataStore
        self.historyStore = historyStore
        self.panoramaFinder = PanoramaFinder(countryDataStore: countryDataStore)

        self.browserAPIKey = defaults.string(forKey: DefaultsKey.browserAPIKey) ?? ""
        self.metadataAPIKey = defaults.string(forKey: DefaultsKey.metadataAPIKey) ?? ""
        self.selectedContinentId = defaults.string(forKey: DefaultsKey.selectedContinentId) ?? ""
        self.selectedCountryId = defaults.string(forKey: DefaultsKey.selectedCountryId) ?? ""

        loadLocalData()
    }

    var hasBrowserAPIKey: Bool {
        !browserAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasMetadataAPIKey: Bool {
        !metadataAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        panorama = entry.panorama
        statusText = "Revisited \(entry.areaLabel)."
        activePanel = .none
    }

    func randomPlace() {
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
        let metadataAPIKey = metadataAPIKey

        Task {
            do {
                let next = try await panoramaFinder.findRandomPanorama(
                    metadataAPIKey: metadataAPIKey,
                    selection: selection
                )
                panorama = next
                history = try historyStore.append(next)
                statusText = "\(next.areaLabel) · \(next.attempts) \(next.attempts == 1 ? "try" : "tries")"
                activePanel = .none
            } catch {
                errorText = error.localizedDescription
                statusText = error.localizedDescription
            }

            isLoading = false
        }
    }

    func importEnvFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = "Import .env"
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let values = try EnvFile.parseFile(at: url)
            if let browser = values["VITE_GOOGLE_MAPS_API_KEY"] {
                browserAPIKey = browser
            }
            if let metadata = values["GOOGLE_STREET_VIEW_METADATA_API_KEY"] {
                metadataAPIKey = metadata
            }
            statusText = "Imported API keys from \(url.lastPathComponent)."
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
