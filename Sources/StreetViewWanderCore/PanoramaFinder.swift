import Foundation

public enum PanoramaFinderError: LocalizedError {
    case missingMetadataKey
    case invalidLocationFilter(String)
    case noPanoramaFound(Int, String)
    case googleRequestFailed(Int)
    case googleResponseInvalid
    case samplingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingMetadataKey:
            "Add GOOGLE_STREET_VIEW_METADATA_API_KEY in Settings first."
        case .invalidLocationFilter(let message):
            message
        case .noPanoramaFound(let attempts, let status):
            "No panorama found after \(attempts) tries. Last status: \(status)."
        case .googleRequestFailed(let statusCode):
            "Google metadata request failed with HTTP \(statusCode)."
        case .googleResponseInvalid:
            "Google metadata response was invalid."
        case .samplingFailed(let country):
            "Could not sample a point inside \(country)."
        }
    }
}

public struct SearchCandidate: Equatable {
    public var requestedLocation: PanoramaLocation
    public var areaLabel: String
    public var scopeLabel: String
    public var continentLabel: String?
    public var countryLabel: String?
}

public actor PanoramaFinder {
    private let countryDataStore: CountryDataStore
    private let session: URLSession

    public init(countryDataStore: CountryDataStore = CountryDataStore(), session: URLSession = .shared) {
        self.countryDataStore = countryDataStore
        self.session = session
    }

    public func findRandomPanorama(
        metadataAPIKey: String,
        selection: SearchSelection,
        recentContinents: [String] = []
    ) async throws -> Panorama {
        let apiKey = metadataAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw PanoramaFinderError.missingMetadataKey
        }

        let countries = try countryDataStore.loadCountries()
        let scope = try SearchScope(countries: countries, selection: selection)
        let globalPlan = try SearchSampler.globalSearchPlan(scope: scope, recentContinents: recentContinents)
        var lastStatus = "NO_ATTEMPTS"

        for attempt in 1...SearchSampler.maxAttempts {
            let candidate = try SearchSampler.pickCandidate(
                scope: scope,
                recentContinents: recentContinents,
                globalPlan: globalPlan,
                attempt: attempt
            )
            let metadata = try await metadata(apiKey: apiKey, location: candidate.requestedLocation)
            lastStatus = metadata.errorMessage ?? metadata.status

            if metadata.status == "OK",
               let location = metadata.location,
               let panoId = metadata.panoId,
               let resolvedCandidate = SearchSampler.resolveCandidate(
                    candidate,
                    for: location,
                    countries: countries,
                    selection: selection
               ) {
                return Panorama(
                    panoId: panoId,
                    location: location,
                    requestedLocation: candidate.requestedLocation,
                    heading: Int.random(in: 0..<360),
                    pitch: 0,
                    fov: 85,
                    date: metadata.date,
                    copyright: metadata.copyright,
                    areaLabel: resolvedCandidate.areaLabel,
                    scopeLabel: resolvedCandidate.scopeLabel,
                    continentLabel: resolvedCandidate.continentLabel,
                    countryLabel: resolvedCandidate.countryLabel,
                    attempts: attempt
                )
            }
        }

        throw PanoramaFinderError.noPanoramaFound(SearchSampler.maxAttempts, lastStatus)
    }

    private func metadata(apiKey: String, location: PanoramaLocation) async throws -> PanoramaMetadata {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/streetview/metadata")
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "location", value: "\(location.lat),\(location.lng)"),
            URLQueryItem(name: "radius", value: "800"),
            URLQueryItem(name: "source", value: "outdoor")
        ]

        guard let url = components?.url else {
            throw PanoramaFinderError.googleResponseInvalid
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw PanoramaFinderError.googleResponseInvalid
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PanoramaFinderError.googleRequestFailed(http.statusCode)
        }

        return try JSONDecoder().decode(PanoramaMetadata.self, from: data)
    }
}

public enum SearchSampler {
    public static let maxAttempts = 90
    // Keep most early retries inside one balanced continent so high-coverage regions do not steal every success.
    private static let focusedGlobalAttempts = 36
    private static let pointSampleAttempts = 40
    private static let recentContinentWindow = 60
    private static let recentContinentPenalty = 0.65
    private static let antarcticaWorldWeight = 0.05
    private static let primaryWorldContinents: Set<String> = [
        "Africa",
        "Asia",
        "Europe",
        "North America",
        "Oceania",
        "South America"
    ]

    struct GlobalSearchPlan: Equatable {
        fileprivate var continents: [String]

        fileprivate func continent(forAttempt attempt: Int) -> String? {
            guard let focusedContinent = continents.first else {
                return nil
            }
            guard continents.count > 1 else {
                return focusedContinent
            }

            let focusedAttempts = focusedContinent == "Antarctica" ? 8 : SearchSampler.focusedGlobalAttempts
            if attempt <= focusedAttempts {
                return focusedContinent
            }

            let fallbackContinents = continents.dropFirst()
            let fallbackIndex = (attempt - focusedAttempts - 1) % fallbackContinents.count
            return Array(fallbackContinents)[fallbackIndex]
        }
    }

    public static func pickCandidate(
        countries: [CountryArea],
        selection: SearchSelection,
        recentContinents: [String] = []
    ) throws -> SearchCandidate {
        try pickCandidate(
            scope: SearchScope(countries: countries, selection: selection),
            recentContinents: recentContinents
        )
    }

    public static func pickCandidates(
        countries: [CountryArea],
        selection: SearchSelection,
        recentContinents: [String] = [],
        attempts: ClosedRange<Int>
    ) throws -> [SearchCandidate] {
        let scope = try SearchScope(countries: countries, selection: selection)
        let globalPlan = try globalSearchPlan(scope: scope, recentContinents: recentContinents)
        return try attempts.map {
            try pickCandidate(
                scope: scope,
                recentContinents: recentContinents,
                globalPlan: globalPlan,
                attempt: $0
            )
        }
    }

    static func globalSearchPlan(scope: SearchScope, recentContinents: [String]) throws -> GlobalSearchPlan? {
        guard case .global(_, let countries) = scope else {
            return nil
        }
        let countriesByContinent = Dictionary(grouping: countries, by: \.continent)
        return GlobalSearchPlan(continents: try weightedContinentOrder(
            countriesByContinent: countriesByContinent,
            recentContinents: recentContinents
        ))
    }

    static func pickCandidate(
        scope: SearchScope,
        recentContinents: [String] = [],
        globalPlan: GlobalSearchPlan? = nil,
        attempt: Int = 1
    ) throws -> SearchCandidate {
        switch scope {
        case .global(let label, let countries):
            let countriesByContinent = Dictionary(grouping: countries, by: \.continent)
            let continent = try globalPlan?.continent(forAttempt: attempt)
                ?? pickBalancedContinent(
                    countriesByContinent: countriesByContinent,
                    recentContinents: recentContinents
                )
            return try pickGlobalCandidate(label: label, countries: countries, continent: continent)
        case .countries(let label, let countries, let selectedCountry):
            let country = try pickWeighted(countries) { countrySamplingWeight($0) }
            let areaLabel = selectedCountry == nil ? "\(label) · \(country.name)" : country.name
            return SearchCandidate(
                requestedLocation: try pickPoint(in: country),
                areaLabel: areaLabel,
                scopeLabel: label,
                continentLabel: country.continent,
                countryLabel: country.name
            )
        }
    }

    public static func resolveCandidate(
        _ candidate: SearchCandidate,
        for location: PanoramaLocation,
        countries: [CountryArea],
        selection: SearchSelection
    ) -> SearchCandidate? {
        guard let actualCountry = country(containing: location, countries: countries) else {
            if selection.countryId != nil || selection.continentId != nil {
                return nil
            }
            return candidate
        }

        if let countryId = selection.countryId, actualCountry.id != countryId {
            return nil
        }
        if let continentId = selection.continentId, actualCountry.continent != continentId {
            return nil
        }

        var resolvedCandidate = candidate
        resolvedCandidate.continentLabel = actualCountry.continent
        resolvedCandidate.countryLabel = actualCountry.name
        if selection.countryId != nil {
            resolvedCandidate.areaLabel = actualCountry.name
        } else if selection.continentId != nil {
            resolvedCandidate.areaLabel = "\(actualCountry.continent) · \(actualCountry.name)"
        } else {
            resolvedCandidate.areaLabel = actualCountry.name
        }
        return resolvedCandidate
    }

    private static func pickGlobalCandidate(
        label: String,
        countries: [CountryArea],
        continent: String
    ) throws -> SearchCandidate {
        let scopedCountries = countries.filter { $0.continent == continent }
        guard !scopedCountries.isEmpty else {
            throw PanoramaFinderError.invalidLocationFilter("Unknown continent: \(continent)")
        }

        let country = try pickWeighted(scopedCountries) { countrySamplingWeight($0) }
        return SearchCandidate(
            requestedLocation: try pickPoint(in: country),
            areaLabel: country.name,
            scopeLabel: label,
            continentLabel: country.continent,
            countryLabel: country.name
        )
    }

    private static func pickPoint(in country: CountryArea) throws -> PanoramaLocation {
        for _ in 0..<pointSampleAttempts {
            let part = try pickWeighted(country.parts) { $0.weight }
            if let point = pickPoint(in: part) {
                return point
            }
        }

        throw PanoramaFinderError.samplingFailed(country.name)
    }

    private static func pickPoint(in part: CountryPart) -> PanoramaLocation? {
        let west = part.bbox[0]
        let south = part.bbox[1]
        let east = part.bbox[2]
        let north = part.bbox[3]

        for _ in 0..<pointSampleAttempts {
            let point = PanoramaLocation(
                lat: Double.random(in: south...north),
                lng: Double.random(in: west...east)
            )

            if isPoint(point, in: part) {
                return point
            }
        }

        return nil
    }

    private static func isPoint(_ point: PanoramaLocation, in part: CountryPart) -> Bool {
        isPoint(point, inRing: part.outer)
            && part.holes.allSatisfy { !isPoint(point, inRing: $0) }
    }

    private static func isPoint(_ point: PanoramaLocation, in country: CountryArea) -> Bool {
        country.parts.contains { isPoint(point, in: $0) }
    }

    private static func country(containing point: PanoramaLocation, countries: [CountryArea]) -> CountryArea? {
        countries.first { isPoint(point, in: $0) }
    }

    private static func isPoint(_ point: PanoramaLocation, inRing ring: [[Double]]) -> Bool {
        guard ring.count >= 3 else {
            return false
        }

        var isInside = false
        var previousIndex = ring.count - 1

        for index in ring.indices {
            let current = ring[index]
            let previous = ring[previousIndex]
            previousIndex = index

            guard current.count >= 2, previous.count >= 2 else {
                continue
            }

            let currentLng = current[0]
            let currentLat = current[1]
            let previousLng = previous[0]
            let previousLat = previous[1]
            let crossesLatitude = (currentLat > point.lat) != (previousLat > point.lat)

            if !crossesLatitude {
                continue
            }

            let intersectionLng =
                ((previousLng - currentLng) * (point.lat - currentLat)) /
                (previousLat - currentLat) + currentLng

            if point.lng < intersectionLng {
                isInside.toggle()
            }
        }

        return isInside
    }

    private static func pickWeighted<T>(_ items: [T], weight: (T) -> Double) throws -> T {
        guard let fallback = items.last else {
            throw PanoramaFinderError.invalidLocationFilter("No search area is available.")
        }

        let totalWeight = items.reduce(0) { $0 + max(0, weight($1)) }
        guard totalWeight > 0 else {
            return fallback
        }

        var threshold = Double.random(in: 0..<totalWeight)
        for item in items {
            threshold -= max(0, weight(item))
            if threshold <= 0 {
                return item
            }
        }

        return fallback
    }

    private static func weightedContinentOrder(
        countriesByContinent: [String: [CountryArea]],
        recentContinents: [String]
    ) throws -> [String] {
        var remainingContinents = countriesByContinent.keys.sorted()
        var orderedContinents: [String] = []

        while !remainingContinents.isEmpty {
            let nextContinent = try pickWeighted(remainingContinents) {
                balancedContinentWeight(
                    continent: $0,
                    availableContinentCount: remainingContinents.count,
                    recentContinents: recentContinents
                )
            }
            orderedContinents.append(nextContinent)
            remainingContinents.removeAll { $0 == nextContinent }
        }

        return orderedContinents
    }

    private static func pickBalancedContinent(
        countriesByContinent: [String: [CountryArea]],
        recentContinents: [String]
    ) throws -> String {
        try pickWeighted(countriesByContinent.keys.sorted()) {
            balancedContinentWeight(
                continent: $0,
                availableContinentCount: countriesByContinent.count,
                recentContinents: recentContinents
            )
        }
    }

    private static func balancedContinentWeight(
        continent: String,
        availableContinentCount: Int,
        recentContinents: [String]
    ) -> Double {
        let baseWeight = primaryWorldContinents.contains(continent) ? 1.0 : antarcticaWorldWeight
        let recentCounts = Dictionary(
            grouping: recentContinents.prefix(recentContinentWindow),
            by: { $0 }
        ).mapValues(\.count)
        let consideredRecentCount = recentCounts.values.reduce(0, +)
        guard consideredRecentCount > 0 else {
            return baseWeight
        }

        let expectedCount = Double(consideredRecentCount) / Double(max(1, availableContinentCount))
        let overrepresentedCount = max(0, Double(recentCounts[continent, default: 0]) - expectedCount)
        return baseWeight / (1 + overrepresentedCount * recentContinentPenalty)
    }

    private static func countrySamplingWeight(_ country: CountryArea) -> Double {
        // Blend equal-country sampling with softened area and population signals so large countries do not dominate.
        let areaSignal = pow(max(0.0001, country.weight), 0.25)
        let populationSignal = sqrt(log10(max(10, country.population)))
        return 1 + areaSignal + populationSignal
    }
}

enum SearchScope: Equatable {
    case global(label: String, countries: [CountryArea])
    case countries(label: String, countries: [CountryArea], selectedCountry: CountryArea?)

    init(countries: [CountryArea], selection: SearchSelection) throws {
        if let countryId = selection.countryId {
            guard let country = countries.first(where: { $0.id == countryId }) else {
                throw PanoramaFinderError.invalidLocationFilter("Unknown country: \(countryId)")
            }

            if let continentId = selection.continentId, country.continent != continentId {
                throw PanoramaFinderError.invalidLocationFilter("\(country.name) is not in \(continentId).")
            }

            self = .countries(label: country.name, countries: [country], selectedCountry: country)
            return
        }

        if let continentId = selection.continentId {
            let scopedCountries = countries.filter { $0.continent == continentId }
            guard !scopedCountries.isEmpty else {
                throw PanoramaFinderError.invalidLocationFilter("Unknown continent: \(continentId)")
            }
            self = .countries(label: continentId, countries: scopedCountries, selectedCountry: nil)
            return
        }

        self = .global(label: "World", countries: countries)
    }
}

struct PanoramaMetadata: Decodable {
    var status: String
    var panoId: String?
    var location: PanoramaLocation?
    var date: String?
    var copyright: String?
    var errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case status
        case panoId = "pano_id"
        case location
        case date
        case copyright
        case errorMessage = "error_message"
    }
}
