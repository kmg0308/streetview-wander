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
    public var densityTier: SearchDensityTier
    public var areaLabel: String
    public var scopeLabel: String
    public var continentLabel: String?
    public var countryLabel: String?

    public var searchRadius: Int {
        densityTier.searchRadius
    }
}

public enum SearchDensityTier: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case tight
    case local
    case wide

    public var searchRadius: Int {
        switch self {
        case .tight:
            120
        case .local:
            350
        case .wide:
            800
        }
    }

    public static func classify(
        requestedLocation: PanoramaLocation,
        panoramaLocation: PanoramaLocation
    ) -> SearchDensityTier {
        let distance = distanceMeters(from: requestedLocation, to: panoramaLocation)
        if distance <= Double(SearchDensityTier.tight.searchRadius) {
            return .tight
        }
        if distance <= Double(SearchDensityTier.local.searchRadius) {
            return .local
        }
        return .wide
    }

    public static func distanceMeters(from start: PanoramaLocation, to end: PanoramaLocation) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let startLat = radians(start.lat)
        let endLat = radians(end.lat)
        let deltaLat = radians(end.lat - start.lat)
        let deltaLng = radians(end.lng - start.lng)

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(startLat) * cos(endLat) * sin(deltaLng / 2) * sin(deltaLng / 2)
        let clampedA = min(1, max(0, a))
        let c = 2 * atan2(sqrt(clampedA), sqrt(1 - clampedA))
        return earthRadiusMeters * c
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
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
        recentContinents: [String] = [],
        recentCountries: [String] = [],
        recentDensityTiers: [SearchDensityTier] = [],
        onMetadataRequest: (@Sendable () async -> Void)? = nil
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
                recentCountries: recentCountries,
                recentDensityTiers: recentDensityTiers,
                globalPlan: globalPlan,
                attempt: attempt
            )
            let metadata = try await metadata(
                apiKey: apiKey,
                location: candidate.requestedLocation,
                radius: candidate.searchRadius,
                onRequest: onMetadataRequest
            )
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

    private func metadata(
        apiKey: String,
        location: PanoramaLocation,
        radius: Int,
        onRequest: (@Sendable () async -> Void)?
    ) async throws -> PanoramaMetadata {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/streetview/metadata")
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "location", value: "\(location.lat),\(location.lng)"),
            URLQueryItem(name: "radius", value: "\(radius)"),
            URLQueryItem(name: "source", value: "outdoor")
        ]

        guard let url = components?.url else {
            throw PanoramaFinderError.googleResponseInvalid
        }

        await onRequest?()
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
    private static let recentCountryWindow = 80
    private static let recentCountryPenalty = 0.45
    private static let recentDensityWindow = 60
    private static let recentDensityPenalty = 0.85
    private static let densityFocusedAttempts = 6
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
        recentContinents: [String] = [],
        recentCountries: [String] = [],
        recentDensityTiers: [SearchDensityTier] = []
    ) throws -> SearchCandidate {
        try pickCandidate(
            scope: SearchScope(countries: countries, selection: selection),
            recentContinents: recentContinents,
            recentCountries: recentCountries,
            recentDensityTiers: recentDensityTiers
        )
    }

    public static func pickCandidates(
        countries: [CountryArea],
        selection: SearchSelection,
        recentContinents: [String] = [],
        recentCountries: [String] = [],
        recentDensityTiers: [SearchDensityTier] = [],
        attempts: ClosedRange<Int>
    ) throws -> [SearchCandidate] {
        let scope = try SearchScope(countries: countries, selection: selection)
        let globalPlan = try globalSearchPlan(scope: scope, recentContinents: recentContinents)
        return try attempts.map {
            try pickCandidate(
                scope: scope,
                recentContinents: recentContinents,
                recentCountries: recentCountries,
                recentDensityTiers: recentDensityTiers,
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
        recentCountries: [String] = [],
        recentDensityTiers: [SearchDensityTier] = [],
        globalPlan: GlobalSearchPlan? = nil,
        attempt: Int = 1
    ) throws -> SearchCandidate {
        let densityTier = try pickDensityTier(recentDensityTiers: recentDensityTiers, attempt: attempt)

        switch scope {
        case .global(let label, let countries):
            let countriesByContinent = Dictionary(grouping: countries, by: \.continent)
            let continent = try globalPlan?.continent(forAttempt: attempt)
                ?? pickBalancedContinent(
                    countriesByContinent: countriesByContinent,
                    recentContinents: recentContinents
                )
            return try pickGlobalCandidate(
                label: label,
                countries: countries,
                continent: continent,
                densityTier: densityTier,
                recentCountries: recentCountries
            )
        case .countries(let label, let countries, let selectedCountry):
            let country = try pickWeighted(countries) {
                countrySamplingWeight(
                    $0,
                    availableCountryCount: countries.count,
                    recentCountries: recentCountries
                )
            }
            let areaLabel = selectedCountry == nil ? "\(label) · \(country.name)" : country.name
            return SearchCandidate(
                requestedLocation: try pickPoint(in: country),
                densityTier: densityTier,
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
        continent: String,
        densityTier: SearchDensityTier,
        recentCountries: [String]
    ) throws -> SearchCandidate {
        let scopedCountries = countries.filter { $0.continent == continent }
        guard !scopedCountries.isEmpty else {
            throw PanoramaFinderError.invalidLocationFilter("Unknown continent: \(continent)")
        }

        let country = try pickWeighted(scopedCountries) {
            countrySamplingWeight(
                $0,
                availableCountryCount: scopedCountries.count,
                recentCountries: recentCountries
            )
        }
        return SearchCandidate(
            requestedLocation: try pickPoint(in: country),
            densityTier: densityTier,
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

    private static func pickDensityTier(
        recentDensityTiers: [SearchDensityTier],
        attempt: Int
    ) throws -> SearchDensityTier {
        try pickWeighted(SearchDensityTier.allCases) {
            densityTierWeight($0, recentDensityTiers: recentDensityTiers, attempt: attempt)
        }
    }

    private static func densityTierWeight(
        _ tier: SearchDensityTier,
        recentDensityTiers: [SearchDensityTier],
        attempt: Int
    ) -> Double {
        let baseWeight = densityTierBaseWeight(tier, attempt: attempt)
        let recentCounts = Dictionary(
            grouping: recentDensityTiers.prefix(recentDensityWindow),
            by: { $0 }
        ).mapValues(\.count)
        let consideredRecentCount = recentCounts.values.reduce(0, +)
        guard consideredRecentCount > 0 else {
            return baseWeight
        }

        let expectedCount = Double(consideredRecentCount) / Double(SearchDensityTier.allCases.count)
        let overrepresentedCount = max(0, Double(recentCounts[tier, default: 0]) - expectedCount)
        return baseWeight / (1 + overrepresentedCount * recentDensityPenalty)
    }

    private static func densityTierBaseWeight(_ tier: SearchDensityTier, attempt: Int) -> Double {
        if attempt <= densityFocusedAttempts {
            switch tier {
            case .tight:
                return 0.08
            case .local:
                return 0.22
            case .wide:
                return 0.70
            }
        }

        switch tier {
        case .tight:
            return 0.02
        case .local:
            return 0.08
        case .wide:
            return 0.90
        }
    }

    private static func countrySamplingWeight(
        _ country: CountryArea,
        availableCountryCount: Int,
        recentCountries: [String]
    ) -> Double {
        // Blend equal-country sampling with softened area and population signals so large countries do not dominate.
        let areaSignal = pow(max(0.0001, country.weight), 0.25)
        let populationSignal = sqrt(log10(max(10, country.population)))
        let baseWeight = 1 + areaSignal + populationSignal
        let recentCounts = Dictionary(
            grouping: recentCountries.prefix(recentCountryWindow),
            by: { $0 }
        ).mapValues(\.count)
        let consideredRecentCount = recentCounts.values.reduce(0, +)
        guard consideredRecentCount > 0 else {
            return baseWeight
        }

        let expectedCount = Double(consideredRecentCount) / Double(max(1, availableCountryCount))
        let overrepresentedCount = max(0, Double(recentCounts[country.name, default: 0]) - expectedCount)
        return baseWeight / (1 + overrepresentedCount * recentCountryPenalty)
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
