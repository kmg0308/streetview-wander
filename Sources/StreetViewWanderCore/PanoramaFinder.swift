import Foundation

public enum PanoramaFinderError: LocalizedError {
    case missingMetadataKey
    case invalidLocationFilter(String)
    case noPanoramaFound(Int, String)
    case metadataRequestLimitReached
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
        case .metadataRequestLimitReached:
            "Metadata request limit reached. Increase the limit in Settings or reset the used count."
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
    public var sceneKind: SearchSceneKind
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
        recentSceneKinds: [SearchSceneKind] = [],
        maxMetadataRequests: Int? = nil,
        onMetadataRequest: (@Sendable () async -> Void)? = nil
    ) async throws -> Panorama {
        let apiKey = metadataAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw PanoramaFinderError.missingMetadataKey
        }
        if let maxMetadataRequests, maxMetadataRequests <= 0 {
            throw PanoramaFinderError.metadataRequestLimitReached
        }

        let countries = try countryDataStore.loadCountries()
        let scope = try SearchScope(countries: countries, selection: selection)
        let globalPlan = try SearchSampler.globalSearchPlan(scope: scope, recentContinents: recentContinents)
        var lastStatus = "NO_ATTEMPTS"
        let attemptLimit = min(SearchSampler.maxAttempts, maxMetadataRequests ?? SearchSampler.maxAttempts)

        for attempt in 1...attemptLimit {
            let candidate = try SearchSampler.pickCandidate(
                scope: scope,
                recentContinents: recentContinents,
                recentCountries: recentCountries,
                recentDensityTiers: recentDensityTiers,
                recentSceneKinds: recentSceneKinds,
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
                    sceneKind: candidate.sceneKind,
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

        throw PanoramaFinderError.noPanoramaFound(attemptLimit, lastStatus)
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
    public static let maxAttempts = 32
    // Keep most early retries inside one balanced continent so high-coverage regions do not steal every success.
    private static let focusedGlobalAttempts = 18
    private static let pointSampleAttempts = 40
    private static let recentContinentWindow = 60
    private static let recentContinentPenalty = 0.65
    private static let recentCountryWindow = 80
    private static let recentCountryPenalty = 0.45
    private static let recentDensityWindow = 60
    private static let recentDensityPenalty = 0.85
    private static let recentSceneWindow = 80
    private static let recentScenePenalty = 0.75
    private static let antarcticaWorldWeight = 0.05
    private static let primaryWorldContinents: Set<String> = [
        "Africa",
        "Asia",
        "Europe",
        "North America",
        "Oceania",
        "South America"
    ]

    private struct CityAnchor {
        var countryId: String
        var name: String
        var location: PanoramaLocation
    }

    private static let cityAnchors: [CityAnchor] = [
        CityAnchor(countryId: "ARG", name: "Buenos Aires", location: PanoramaLocation(lat: -34.6037, lng: -58.3816)),
        CityAnchor(countryId: "AUS", name: "Sydney", location: PanoramaLocation(lat: -33.8688, lng: 151.2093)),
        CityAnchor(countryId: "AUS", name: "Melbourne", location: PanoramaLocation(lat: -37.8136, lng: 144.9631)),
        CityAnchor(countryId: "AUS", name: "Brisbane", location: PanoramaLocation(lat: -27.4698, lng: 153.0251)),
        CityAnchor(countryId: "AUS", name: "Perth", location: PanoramaLocation(lat: -31.9523, lng: 115.8613)),
        CityAnchor(countryId: "AUT", name: "Vienna", location: PanoramaLocation(lat: 48.2082, lng: 16.3738)),
        CityAnchor(countryId: "BEL", name: "Brussels", location: PanoramaLocation(lat: 50.8503, lng: 4.3517)),
        CityAnchor(countryId: "BRA", name: "Sao Paulo", location: PanoramaLocation(lat: -23.5558, lng: -46.6396)),
        CityAnchor(countryId: "BRA", name: "Rio de Janeiro", location: PanoramaLocation(lat: -22.9068, lng: -43.1729)),
        CityAnchor(countryId: "BRA", name: "Brasilia", location: PanoramaLocation(lat: -15.7939, lng: -47.8828)),
        CityAnchor(countryId: "CAN", name: "Toronto", location: PanoramaLocation(lat: 43.6532, lng: -79.3832)),
        CityAnchor(countryId: "CAN", name: "Vancouver", location: PanoramaLocation(lat: 49.2827, lng: -123.1207)),
        CityAnchor(countryId: "CAN", name: "Montreal", location: PanoramaLocation(lat: 45.5019, lng: -73.5674)),
        CityAnchor(countryId: "CAN", name: "Calgary", location: PanoramaLocation(lat: 51.0447, lng: -114.0719)),
        CityAnchor(countryId: "CHE", name: "Zurich", location: PanoramaLocation(lat: 47.3769, lng: 8.5417)),
        CityAnchor(countryId: "CHE", name: "Geneva", location: PanoramaLocation(lat: 46.2044, lng: 6.1432)),
        CityAnchor(countryId: "CHL", name: "Santiago", location: PanoramaLocation(lat: -33.4489, lng: -70.6693)),
        CityAnchor(countryId: "COL", name: "Bogota", location: PanoramaLocation(lat: 4.7110, lng: -74.0721)),
        CityAnchor(countryId: "COL", name: "Medellin", location: PanoramaLocation(lat: 6.2442, lng: -75.5812)),
        CityAnchor(countryId: "CZE", name: "Prague", location: PanoramaLocation(lat: 50.0755, lng: 14.4378)),
        CityAnchor(countryId: "DEU", name: "Berlin", location: PanoramaLocation(lat: 52.5200, lng: 13.4050)),
        CityAnchor(countryId: "DEU", name: "Munich", location: PanoramaLocation(lat: 48.1351, lng: 11.5820)),
        CityAnchor(countryId: "DEU", name: "Hamburg", location: PanoramaLocation(lat: 53.5511, lng: 9.9937)),
        CityAnchor(countryId: "DNK", name: "Copenhagen", location: PanoramaLocation(lat: 55.6761, lng: 12.5683)),
        CityAnchor(countryId: "ECU", name: "Quito", location: PanoramaLocation(lat: -0.1807, lng: -78.4678)),
        CityAnchor(countryId: "ESP", name: "Madrid", location: PanoramaLocation(lat: 40.4168, lng: -3.7038)),
        CityAnchor(countryId: "ESP", name: "Barcelona", location: PanoramaLocation(lat: 41.3874, lng: 2.1686)),
        CityAnchor(countryId: "FIN", name: "Helsinki", location: PanoramaLocation(lat: 60.1699, lng: 24.9384)),
        CityAnchor(countryId: "FRA", name: "Paris", location: PanoramaLocation(lat: 48.8566, lng: 2.3522)),
        CityAnchor(countryId: "FRA", name: "Lyon", location: PanoramaLocation(lat: 45.7640, lng: 4.8357)),
        CityAnchor(countryId: "FRA", name: "Marseille", location: PanoramaLocation(lat: 43.2965, lng: 5.3698)),
        CityAnchor(countryId: "GBR", name: "London", location: PanoramaLocation(lat: 51.5074, lng: -0.1278)),
        CityAnchor(countryId: "GBR", name: "Edinburgh", location: PanoramaLocation(lat: 55.9533, lng: -3.1883)),
        CityAnchor(countryId: "GHA", name: "Accra", location: PanoramaLocation(lat: 5.6037, lng: -0.1870)),
        CityAnchor(countryId: "GRC", name: "Athens", location: PanoramaLocation(lat: 37.9838, lng: 23.7275)),
        CityAnchor(countryId: "HUN", name: "Budapest", location: PanoramaLocation(lat: 47.4979, lng: 19.0402)),
        CityAnchor(countryId: "IDN", name: "Jakarta", location: PanoramaLocation(lat: -6.2088, lng: 106.8456)),
        CityAnchor(countryId: "IDN", name: "Bandung", location: PanoramaLocation(lat: -6.9175, lng: 107.6191)),
        CityAnchor(countryId: "IRL", name: "Dublin", location: PanoramaLocation(lat: 53.3498, lng: -6.2603)),
        CityAnchor(countryId: "ISR", name: "Tel Aviv", location: PanoramaLocation(lat: 32.0853, lng: 34.7818)),
        CityAnchor(countryId: "ITA", name: "Rome", location: PanoramaLocation(lat: 41.9028, lng: 12.4964)),
        CityAnchor(countryId: "ITA", name: "Milan", location: PanoramaLocation(lat: 45.4642, lng: 9.1900)),
        CityAnchor(countryId: "JPN", name: "Tokyo", location: PanoramaLocation(lat: 35.6762, lng: 139.6503)),
        CityAnchor(countryId: "JPN", name: "Osaka", location: PanoramaLocation(lat: 34.6937, lng: 135.5023)),
        CityAnchor(countryId: "JPN", name: "Kyoto", location: PanoramaLocation(lat: 35.0116, lng: 135.7681)),
        CityAnchor(countryId: "KEN", name: "Nairobi", location: PanoramaLocation(lat: -1.2921, lng: 36.8219)),
        CityAnchor(countryId: "KOR", name: "Seoul", location: PanoramaLocation(lat: 37.5665, lng: 126.9780)),
        CityAnchor(countryId: "KOR", name: "Busan", location: PanoramaLocation(lat: 35.1796, lng: 129.0756)),
        CityAnchor(countryId: "MEX", name: "Mexico City", location: PanoramaLocation(lat: 19.4326, lng: -99.1332)),
        CityAnchor(countryId: "MEX", name: "Guadalajara", location: PanoramaLocation(lat: 20.6597, lng: -103.3496)),
        CityAnchor(countryId: "MYS", name: "Kuala Lumpur", location: PanoramaLocation(lat: 3.1390, lng: 101.6869)),
        CityAnchor(countryId: "NLD", name: "Amsterdam", location: PanoramaLocation(lat: 52.3676, lng: 4.9041)),
        CityAnchor(countryId: "NLD", name: "Rotterdam", location: PanoramaLocation(lat: 51.9244, lng: 4.4777)),
        CityAnchor(countryId: "NOR", name: "Oslo", location: PanoramaLocation(lat: 59.9139, lng: 10.7522)),
        CityAnchor(countryId: "NZL", name: "Auckland", location: PanoramaLocation(lat: -36.8509, lng: 174.7645)),
        CityAnchor(countryId: "NZL", name: "Wellington", location: PanoramaLocation(lat: -41.2865, lng: 174.7762)),
        CityAnchor(countryId: "PER", name: "Lima", location: PanoramaLocation(lat: -12.0464, lng: -77.0428)),
        CityAnchor(countryId: "PHL", name: "Manila", location: PanoramaLocation(lat: 14.5995, lng: 120.9842)),
        CityAnchor(countryId: "POL", name: "Warsaw", location: PanoramaLocation(lat: 52.2297, lng: 21.0122)),
        CityAnchor(countryId: "POL", name: "Krakow", location: PanoramaLocation(lat: 50.0647, lng: 19.9450)),
        CityAnchor(countryId: "PRT", name: "Lisbon", location: PanoramaLocation(lat: 38.7223, lng: -9.1393)),
        CityAnchor(countryId: "PRT", name: "Porto", location: PanoramaLocation(lat: 41.1579, lng: -8.6291)),
        CityAnchor(countryId: "SWE", name: "Stockholm", location: PanoramaLocation(lat: 59.3293, lng: 18.0686)),
        CityAnchor(countryId: "THA", name: "Bangkok", location: PanoramaLocation(lat: 13.7563, lng: 100.5018)),
        CityAnchor(countryId: "TUR", name: "Istanbul", location: PanoramaLocation(lat: 41.0082, lng: 28.9784)),
        CityAnchor(countryId: "TWN", name: "Taipei", location: PanoramaLocation(lat: 25.0330, lng: 121.5654)),
        CityAnchor(countryId: "URY", name: "Montevideo", location: PanoramaLocation(lat: -34.9011, lng: -56.1645)),
        CityAnchor(countryId: "USA", name: "New York", location: PanoramaLocation(lat: 40.7128, lng: -74.0060)),
        CityAnchor(countryId: "USA", name: "Los Angeles", location: PanoramaLocation(lat: 34.0522, lng: -118.2437)),
        CityAnchor(countryId: "USA", name: "Chicago", location: PanoramaLocation(lat: 41.8781, lng: -87.6298)),
        CityAnchor(countryId: "USA", name: "San Francisco", location: PanoramaLocation(lat: 37.7749, lng: -122.4194)),
        CityAnchor(countryId: "USA", name: "Seattle", location: PanoramaLocation(lat: 47.6062, lng: -122.3321)),
        CityAnchor(countryId: "USA", name: "Miami", location: PanoramaLocation(lat: 25.7617, lng: -80.1918)),
        CityAnchor(countryId: "USA", name: "New Orleans", location: PanoramaLocation(lat: 29.9511, lng: -90.0715)),
        CityAnchor(countryId: "VNM", name: "Ho Chi Minh City", location: PanoramaLocation(lat: 10.8231, lng: 106.6297)),
        CityAnchor(countryId: "VNM", name: "Hanoi", location: PanoramaLocation(lat: 21.0278, lng: 105.8342)),
        CityAnchor(countryId: "ZAF", name: "Cape Town", location: PanoramaLocation(lat: -33.9249, lng: 18.4241)),
        CityAnchor(countryId: "ZAF", name: "Johannesburg", location: PanoramaLocation(lat: -26.2041, lng: 28.0473)),
        CityAnchor(countryId: "ZAF", name: "Durban", location: PanoramaLocation(lat: -29.8587, lng: 31.0218))
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
        recentDensityTiers: [SearchDensityTier] = [],
        recentSceneKinds: [SearchSceneKind] = []
    ) throws -> SearchCandidate {
        try pickCandidate(
            scope: SearchScope(countries: countries, selection: selection),
            recentContinents: recentContinents,
            recentCountries: recentCountries,
            recentDensityTiers: recentDensityTiers,
            recentSceneKinds: recentSceneKinds
        )
    }

    public static func pickCandidates(
        countries: [CountryArea],
        selection: SearchSelection,
        recentContinents: [String] = [],
        recentCountries: [String] = [],
        recentDensityTiers: [SearchDensityTier] = [],
        recentSceneKinds: [SearchSceneKind] = [],
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
                recentSceneKinds: recentSceneKinds,
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
        recentSceneKinds: [SearchSceneKind] = [],
        globalPlan: GlobalSearchPlan? = nil,
        attempt: Int = 1
    ) throws -> SearchCandidate {
        let sceneKind = try pickSceneKind(recentSceneKinds: recentSceneKinds, attempt: attempt)
        let densityTier = try pickDensityTier(
            sceneKind: sceneKind,
            recentDensityTiers: recentDensityTiers,
            attempt: attempt
        )

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
                sceneKind: sceneKind,
                densityTier: densityTier,
                recentCountries: recentCountries
            )
        case .countries(let label, let countries, let selectedCountry):
            let country = try pickWeighted(countries) {
                countrySamplingWeight(
                    $0,
                    availableCountryCount: countries.count,
                    recentCountries: recentCountries,
                    sceneKind: sceneKind
                )
            }
            let areaLabel = selectedCountry == nil ? "\(label) · \(country.name)" : country.name
            return SearchCandidate(
                requestedLocation: try pickPoint(in: country, sceneKind: sceneKind),
                sceneKind: sceneKind,
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
        sceneKind: SearchSceneKind,
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
                recentCountries: recentCountries,
                sceneKind: sceneKind
            )
        }
        return SearchCandidate(
            requestedLocation: try pickPoint(in: country, sceneKind: sceneKind),
            sceneKind: sceneKind,
            densityTier: densityTier,
            areaLabel: country.name,
            scopeLabel: label,
            continentLabel: country.continent,
            countryLabel: country.name
        )
    }

    private static func pickPoint(in country: CountryArea, sceneKind: SearchSceneKind) throws -> PanoramaLocation {
        if let anchorPoint = pickAnchorPoint(in: country, sceneKind: sceneKind) {
            return anchorPoint
        }

        for _ in 0..<pointSampleAttempts {
            let part = try pickWeighted(country.parts) { $0.weight }
            if let point = pickPoint(in: part) {
                return point
            }
        }

        throw PanoramaFinderError.samplingFailed(country.name)
    }

    private static func pickAnchorPoint(in country: CountryArea, sceneKind: SearchSceneKind) -> PanoramaLocation? {
        guard sceneKind == .city || sceneKind == .town else {
            return nil
        }
        let anchors = cityAnchors.filter { $0.countryId == country.id }
        guard let anchor = anchors.randomElement() else {
            return nil
        }

        let maxDistanceMeters: Double = sceneKind == .city ? 1_200 : 9_000
        for _ in 0..<pointSampleAttempts {
            let point = jitter(anchor.location, maxDistanceMeters: maxDistanceMeters)
            if isPoint(point, in: country) {
                return point
            }
        }

        return isPoint(anchor.location, in: country) ? anchor.location : nil
    }

    private static func jitter(_ location: PanoramaLocation, maxDistanceMeters: Double) -> PanoramaLocation {
        let angle = Double.random(in: 0..<(2 * .pi))
        let distance = sqrt(Double.random(in: 0...1)) * maxDistanceMeters
        let latMeters = 111_320.0
        let lngMeters = max(1, latMeters * cos(location.lat * .pi / 180))

        return PanoramaLocation(
            lat: location.lat + cos(angle) * distance / latMeters,
            lng: location.lng + sin(angle) * distance / lngMeters
        )
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
        sceneKind: SearchSceneKind,
        recentDensityTiers: [SearchDensityTier],
        attempt: Int
    ) throws -> SearchDensityTier {
        try pickWeighted(SearchDensityTier.allCases) {
            densityTierWeight($0, sceneKind: sceneKind, recentDensityTiers: recentDensityTiers, attempt: attempt)
        }
    }

    private static func densityTierWeight(
        _ tier: SearchDensityTier,
        sceneKind: SearchSceneKind,
        recentDensityTiers: [SearchDensityTier],
        attempt: Int
    ) -> Double {
        let baseWeight = densityTierBaseWeight(tier, sceneKind: sceneKind, attempt: attempt)
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

    private static func densityTierBaseWeight(
        _ tier: SearchDensityTier,
        sceneKind: SearchSceneKind,
        attempt: Int
    ) -> Double {
        let lateAttemptWideBoost = attempt > 8 ? 0.12 : 0
        switch (sceneKind, tier) {
        case (.city, .tight):
            return 0.32
        case (.city, .local):
            return 0.56
        case (.city, .wide):
            return 0.12 + lateAttemptWideBoost
        case (.town, .tight):
            return 0.16
        case (.town, .local):
            return 0.58
        case (.town, .wide):
            return 0.26 + lateAttemptWideBoost
        case (.road, .tight):
            return 0.03
        case (.road, .local):
            return 0.17
        case (.road, .wide):
            return 0.80
        case (.remote, .tight):
            return 0.02
        case (.remote, .local):
            return 0.10
        case (.remote, .wide):
            return 0.88
        }
    }

    private static func pickSceneKind(
        recentSceneKinds: [SearchSceneKind],
        attempt: Int
    ) throws -> SearchSceneKind {
        try pickWeighted(SearchSceneKind.allCases) {
            sceneKindWeight($0, recentSceneKinds: recentSceneKinds, attempt: attempt)
        }
    }

    private static func sceneKindWeight(
        _ sceneKind: SearchSceneKind,
        recentSceneKinds: [SearchSceneKind],
        attempt: Int
    ) -> Double {
        let baseWeight = sceneKindBaseWeight(sceneKind, attempt: attempt)
        let recentCounts = Dictionary(
            grouping: recentSceneKinds.prefix(recentSceneWindow),
            by: { $0 }
        ).mapValues(\.count)
        let consideredRecentCount = recentCounts.values.reduce(0, +)
        guard consideredRecentCount > 0 else {
            return baseWeight
        }

        let expectedCount = Double(consideredRecentCount) / Double(SearchSceneKind.allCases.count)
        let overrepresentedCount = max(0, Double(recentCounts[sceneKind, default: 0]) - expectedCount)
        return baseWeight / (1 + overrepresentedCount * recentScenePenalty)
    }

    private static func sceneKindBaseWeight(_ sceneKind: SearchSceneKind, attempt: Int) -> Double {
        if attempt <= 3 {
            switch sceneKind {
            case .city:
                return 0.42
            case .town:
                return 0.26
            case .road:
                return 0.22
            case .remote:
                return 0.10
            }
        }

        if attempt <= 8 {
            switch sceneKind {
            case .city:
                return 0.30
            case .town:
                return 0.24
            case .road:
                return 0.30
            case .remote:
                return 0.16
            }
        }

        switch sceneKind {
        case .city:
            return 0.18
        case .town:
            return 0.18
        case .road:
            return 0.44
        case .remote:
            return 0.20
        }
    }

    private static func countrySamplingWeight(
        _ country: CountryArea,
        availableCountryCount: Int,
        recentCountries: [String],
        sceneKind: SearchSceneKind
    ) -> Double {
        // Blend equal-country sampling with softened area and population signals so large countries do not dominate.
        let areaSignal = pow(max(0.0001, country.weight), 0.18)
        let populationSignal = sqrt(log10(max(10, country.population)))
        let densitySignal = sqrt(log10(max(10, country.population / max(0.1, country.weight))))
        let anchorCount = cityAnchors.filter { $0.countryId == country.id }.count
        let sceneSignal: Double
        switch sceneKind {
        case .city:
            sceneSignal = anchorCount > 0 ? 1.4 + min(2.2, Double(anchorCount) * 0.28) : 0.20
        case .town:
            sceneSignal = anchorCount > 0 ? 1.1 + min(1.4, Double(anchorCount) * 0.18) : 0.45
        case .road:
            sceneSignal = 1.0
        case .remote:
            sceneSignal = max(0.35, 1.4 - min(1.0, densitySignal * 0.16))
        }
        let baseWeight = (1 + areaSignal + populationSignal + densitySignal * 0.35) * sceneSignal
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
