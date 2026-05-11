import Foundation

public enum CountryDataError: LocalizedError {
    case fileNotFound
    case invalidPart(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            "countries.json was not found."
        case .invalidPart(let country):
            "Country data for \(country) is invalid."
        }
    }
}

public final class CountryDataStore: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedCountries: [CountryArea]?

    public init() {}

    public func loadCountries() throws -> [CountryArea] {
        lock.lock()
        if let cachedCountries {
            lock.unlock()
            return cachedCountries
        }
        lock.unlock()

        guard let url = Self.findCountryDataURL() else {
            throw CountryDataError.fileNotFound
        }

        let data = try Data(contentsOf: url)
        let countries = try JSONDecoder().decode([CountryArea].self, from: data)

        for country in countries {
            for part in country.parts where part.bbox.count != 4 || part.outer.count < 3 {
                throw CountryDataError.invalidPart(country.name)
            }
        }

        lock.lock()
        cachedCountries = countries
        lock.unlock()
        return countries
    }

    public func locationOptions() throws -> LocationOptions {
        let countries = try loadCountries()
        var continentCounts: [String: Int] = [:]

        for country in countries {
            continentCounts[country.continent, default: 0] += 1
        }

        return LocationOptions(
            continents: continentCounts
                .map { ContinentOption(id: $0.key, label: $0.key, countryCount: $0.value) }
                .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending },
            countries: countries
                .map {
                    CountryOption(
                        id: $0.id,
                        code: $0.code,
                        label: $0.name,
                        continent: $0.continent,
                        subregion: $0.subregion
                    )
                }
                .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        )
    }

    private static func findCountryDataURL() -> URL? {
        let fileManager = FileManager.default

        if let override = ProcessInfo.processInfo.environment["STREETVIEW_WANDER_COUNTRY_DATA"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: override)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        let bundleCandidates = [
            Bundle.main.resourceURL?.appendingPathComponent("data/countries.json"),
            Bundle.main.resourceURL?.appendingPathComponent("countries.json")
        ]
        for candidate in bundleCandidates.compactMap(\.self) where fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let repoCandidates = [
            currentDirectory.appendingPathComponent("data/countries.json"),
            currentDirectory.deletingLastPathComponent().appendingPathComponent("data/countries.json")
        ]
        for candidate in repoCandidates where fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        return nil
    }
}
