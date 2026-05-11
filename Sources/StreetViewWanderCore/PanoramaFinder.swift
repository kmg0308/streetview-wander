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
        selection: SearchSelection
    ) async throws -> Panorama {
        let apiKey = metadataAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw PanoramaFinderError.missingMetadataKey
        }

        let countries = try countryDataStore.loadCountries()
        let scope = try SearchScope(countries: countries, selection: selection)
        var lastStatus = "NO_ATTEMPTS"

        for attempt in 1...SearchSampler.maxAttempts {
            let candidate = try SearchSampler.pickCandidate(scope: scope)
            let metadata = try await metadata(apiKey: apiKey, location: candidate.requestedLocation)
            lastStatus = metadata.errorMessage ?? metadata.status

            if metadata.status == "OK",
               let location = metadata.location,
               let panoId = metadata.panoId {
                return Panorama(
                    panoId: panoId,
                    location: location,
                    requestedLocation: candidate.requestedLocation,
                    heading: Int.random(in: 0..<360),
                    pitch: 0,
                    fov: 85,
                    date: metadata.date,
                    copyright: metadata.copyright,
                    areaLabel: candidate.areaLabel,
                    scopeLabel: candidate.scopeLabel,
                    continentLabel: candidate.continentLabel,
                    countryLabel: candidate.countryLabel,
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
    private static let pointSampleAttempts = 40

    public static func pickCandidate(countries: [CountryArea], selection: SearchSelection) throws -> SearchCandidate {
        try pickCandidate(scope: SearchScope(countries: countries, selection: selection))
    }

    static func pickCandidate(scope: SearchScope) throws -> SearchCandidate {
        switch scope {
        case .global(let label):
            let area = try pickWeighted(searchAreas) { $0.weight }
            return SearchCandidate(
                requestedLocation: pickPoint(in: area),
                areaLabel: area.label,
                scopeLabel: label
            )
        case .countries(let label, let countries, let selectedCountry):
            let country = try pickWeighted(countries) { $0.weight }
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

    private static func pickPoint(in bounds: SearchArea) -> PanoramaLocation {
        PanoramaLocation(
            lat: Double.random(in: bounds.south...bounds.north),
            lng: Double.random(in: bounds.west...bounds.east)
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
}

enum SearchScope: Equatable {
    case global(label: String)
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

        self = .global(label: "World")
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

struct SearchArea: Equatable {
    var label: String
    var north: Double
    var south: Double
    var east: Double
    var west: Double
    var weight: Double
}

private let searchAreas: [SearchArea] = [
    SearchArea(label: "Alaska and Yukon", north: 71.5, south: 51.0, east: -129.0, west: -170.0, weight: 1),
    SearchArea(label: "Canada West", north: 60.0, south: 48.0, east: -95.0, west: -140.0, weight: 3),
    SearchArea(label: "Canada East", north: 60.0, south: 42.0, east: -52.0, west: -95.0, weight: 3),
    SearchArea(label: "United States", north: 49.5, south: 24.3, east: -66.5, west: -125.0, weight: 8),
    SearchArea(label: "Mexico", north: 32.8, south: 14.4, east: -86.5, west: -118.5, weight: 5),
    SearchArea(label: "Central America", north: 18.8, south: 7.0, east: -77.0, west: -92.5, weight: 2),
    SearchArea(label: "Caribbean", north: 27.0, south: 10.0, east: -59.0, west: -86.0, weight: 1),
    SearchArea(label: "Greenland and North Atlantic", north: 83.0, south: 59.0, east: -11.0, west: -74.0, weight: 0.5),
    SearchArea(label: "Iceland", north: 66.7, south: 63.0, east: -13.0, west: -24.8, weight: 2),
    SearchArea(label: "British Isles", north: 61.0, south: 49.5, east: 2.3, west: -10.8, weight: 4),
    SearchArea(label: "Iberia", north: 44.2, south: 35.5, east: 4.5, west: -10.0, weight: 4),
    SearchArea(label: "Western Europe", north: 51.8, south: 42.0, east: 8.5, west: -5.5, weight: 5),
    SearchArea(label: "Central Europe", north: 55.2, south: 45.2, east: 20.5, west: 5.5, weight: 5),
    SearchArea(label: "Nordics", north: 71.5, south: 54.5, east: 31.5, west: 4.0, weight: 4),
    SearchArea(label: "Baltics and Poland", north: 59.8, south: 49.0, east: 28.5, west: 14.0, weight: 3),
    SearchArea(label: "Italy and Malta", north: 47.2, south: 35.5, east: 19.0, west: 6.0, weight: 4),
    SearchArea(label: "Balkans", north: 47.5, south: 39.0, east: 29.0, west: 13.0, weight: 3),
    SearchArea(label: "Eastern Europe", north: 56.5, south: 43.0, east: 41.0, west: 20.0, weight: 2),
    SearchArea(label: "Greece and Cyprus", north: 41.9, south: 34.5, east: 35.8, west: 19.0, weight: 3),
    SearchArea(label: "Turkey and Caucasus", north: 43.8, south: 35.5, east: 50.5, west: 25.5, weight: 2),
    SearchArea(label: "Western Russia", north: 68.0, south: 42.0, east: 60.0, west: 29.0, weight: 1),
    SearchArea(label: "Middle East", north: 37.5, south: 12.0, east: 60.5, west: 34.0, weight: 2),
    SearchArea(label: "Central Asia", north: 56.0, south: 35.0, east: 88.0, west: 46.0, weight: 1),
    SearchArea(label: "Northern Asia West", north: 72.0, south: 50.0, east: 105.0, west: 60.0, weight: 0.3),
    SearchArea(label: "Northern Asia East", north: 72.0, south: 42.0, east: 180.0, west: 105.0, weight: 0.3),
    SearchArea(label: "Mongolia and Northern China", north: 54.0, south: 35.0, east: 125.0, west: 88.0, weight: 0.8),
    SearchArea(label: "Eastern China", north: 42.5, south: 18.0, east: 124.5, west: 105.0, weight: 0.4),
    SearchArea(label: "South Asia", north: 36.0, south: 5.0, east: 97.5, west: 66.0, weight: 2),
    SearchArea(label: "Mainland Southeast Asia", north: 28.5, south: -1.5, east: 110.5, west: 92.0, weight: 3),
    SearchArea(label: "Maritime Southeast Asia", north: 8.0, south: -11.0, east: 142.0, west: 95.0, weight: 3),
    SearchArea(label: "Japan and Korea", north: 45.7, south: 31.0, east: 145.8, west: 126.0, weight: 5),
    SearchArea(label: "Taiwan Hong Kong and Macau", north: 25.5, south: 21.8, east: 122.5, west: 113.5, weight: 2),
    SearchArea(label: "Australia and New Zealand", north: -10.0, south: -46.8, east: 178.8, west: 112.8, weight: 5),
    SearchArea(label: "Pacific Islands West", north: 16.0, south: -23.0, east: 180.0, west: 166.0, weight: 0.5),
    SearchArea(label: "Pacific Islands East", north: 22.5, south: -25.0, east: -140.0, west: -180.0, weight: 0.5),
    SearchArea(label: "Northern South America", north: 12.5, south: -8.0, east: -50.0, west: -82.0, weight: 3),
    SearchArea(label: "Brazil", north: 6.0, south: -34.0, east: -34.0, west: -74.0, weight: 4),
    SearchArea(label: "Andes", north: 5.5, south: -56.0, east: -66.0, west: -81.5, weight: 3),
    SearchArea(label: "Southern Cone", north: -17.0, south: -56.0, east: -52.0, west: -76.0, weight: 3),
    SearchArea(label: "North Africa", north: 37.5, south: 15.0, east: 37.0, west: -17.5, weight: 0.8),
    SearchArea(label: "West Africa", north: 16.5, south: -5.0, east: 16.0, west: -18.0, weight: 0.8),
    SearchArea(label: "East Africa", north: 15.0, south: -12.5, east: 52.0, west: 28.0, weight: 0.8),
    SearchArea(label: "Southern Africa", north: -10.0, south: -35.0, east: 40.0, west: 11.0, weight: 2),
    SearchArea(label: "Indian Ocean Islands", north: -4.0, south: -26.0, east: 58.0, west: 43.0, weight: 0.5),
    SearchArea(label: "Antarctic Peninsula", north: -60.0, south: -69.0, east: -52.0, west: -72.0, weight: 0.1),
    SearchArea(label: "Ross Island Antarctica", north: -77.0, south: -78.5, east: 168.0, west: 164.0, weight: 0.1)
]
