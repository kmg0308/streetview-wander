import Foundation

public struct PanoramaLocation: Codable, Equatable, Hashable, Sendable {
    public var lat: Double
    public var lng: Double

    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }
}

public struct Panorama: Codable, Equatable, Hashable, Sendable {
    public var panoId: String
    public var location: PanoramaLocation
    public var requestedLocation: PanoramaLocation
    public var heading: Int
    public var pitch: Int
    public var fov: Int
    public var date: String?
    public var copyright: String?
    public var areaLabel: String
    public var scopeLabel: String
    public var continentLabel: String?
    public var countryLabel: String?
    public var attempts: Int

    public init(
        panoId: String,
        location: PanoramaLocation,
        requestedLocation: PanoramaLocation,
        heading: Int,
        pitch: Int,
        fov: Int,
        date: String?,
        copyright: String?,
        areaLabel: String,
        scopeLabel: String,
        continentLabel: String?,
        countryLabel: String?,
        attempts: Int
    ) {
        self.panoId = panoId
        self.location = location
        self.requestedLocation = requestedLocation
        self.heading = heading
        self.pitch = pitch
        self.fov = fov
        self.date = date
        self.copyright = copyright
        self.areaLabel = areaLabel
        self.scopeLabel = scopeLabel
        self.continentLabel = continentLabel
        self.countryLabel = countryLabel
        self.attempts = attempts
    }
}

public struct HistoryEntry: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var visitedAt: Date
    public var panoId: String
    public var location: PanoramaLocation
    public var requestedLocation: PanoramaLocation
    public var heading: Int
    public var pitch: Int
    public var fov: Int
    public var date: String?
    public var copyright: String?
    public var areaLabel: String
    public var scopeLabel: String
    public var continentLabel: String?
    public var countryLabel: String?
    public var attempts: Int

    public init(id: UUID = UUID(), visitedAt: Date = Date(), panorama: Panorama) {
        self.id = id
        self.visitedAt = visitedAt
        self.panoId = panorama.panoId
        self.location = panorama.location
        self.requestedLocation = panorama.requestedLocation
        self.heading = panorama.heading
        self.pitch = panorama.pitch
        self.fov = panorama.fov
        self.date = panorama.date
        self.copyright = panorama.copyright
        self.areaLabel = panorama.areaLabel
        self.scopeLabel = panorama.scopeLabel
        self.continentLabel = panorama.continentLabel
        self.countryLabel = panorama.countryLabel
        self.attempts = panorama.attempts
    }

    public var panorama: Panorama {
        Panorama(
            panoId: panoId,
            location: location,
            requestedLocation: requestedLocation,
            heading: heading,
            pitch: pitch,
            fov: fov,
            date: date,
            copyright: copyright,
            areaLabel: areaLabel,
            scopeLabel: scopeLabel,
            continentLabel: continentLabel,
            countryLabel: countryLabel,
            attempts: attempts
        )
    }
}

public struct CountryPart: Decodable, Equatable, Sendable {
    public var bbox: [Double]
    public var weight: Double
    public var outer: [[Double]]
    public var holes: [[[Double]]]
}

public struct CountryArea: Decodable, Identifiable, Equatable, Sendable {
    public var id: String
    public var code: String
    public var name: String
    public var continent: String
    public var subregion: String
    public var population: Double
    public var weight: Double
    public var parts: [CountryPart]
}

public struct ContinentOption: Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var countryCount: Int
}

public struct CountryOption: Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var code: String
    public var label: String
    public var continent: String
    public var subregion: String
}

public struct LocationOptions: Equatable, Sendable {
    public var continents: [ContinentOption]
    public var countries: [CountryOption]

    public static let empty = LocationOptions(continents: [], countries: [])
}

public struct SearchSelection: Equatable, Hashable, Sendable {
    public var continentId: String?
    public var countryId: String?

    public init(continentId: String? = nil, countryId: String? = nil) {
        self.continentId = continentId.nilIfBlank
        self.countryId = countryId.nilIfBlank
    }
}

extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
