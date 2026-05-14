import Foundation

public struct PanoramaLocation: Codable, Equatable, Hashable, Sendable {
    public var lat: Double
    public var lng: Double

    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }
}

public enum SearchSceneKind: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case city
    case town
    case road
    case remote

    public var label: String {
        switch self {
        case .city:
            "City"
        case .town:
            "Town edge"
        case .road:
            "Open road"
        case .remote:
            "Remote"
        }
    }
}

public struct Panorama: Codable, Equatable, Hashable, Sendable {
    public var panoId: String
    public var location: PanoramaLocation
    public var requestedLocation: PanoramaLocation
    public var sceneKind: SearchSceneKind?
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
    public var selectionReasonSummary: String?
    public var selectionReasonDetails: [String]?

    public init(
        panoId: String,
        location: PanoramaLocation,
        requestedLocation: PanoramaLocation,
        sceneKind: SearchSceneKind? = nil,
        heading: Int,
        pitch: Int,
        fov: Int,
        date: String?,
        copyright: String?,
        areaLabel: String,
        scopeLabel: String,
        continentLabel: String?,
        countryLabel: String?,
        attempts: Int,
        selectionReasonSummary: String? = nil,
        selectionReasonDetails: [String]? = nil
    ) {
        self.panoId = panoId
        self.location = location
        self.requestedLocation = requestedLocation
        self.sceneKind = sceneKind
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
        self.selectionReasonSummary = selectionReasonSummary
        self.selectionReasonDetails = selectionReasonDetails
    }
}

public struct HistoryEntry: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var visitedAt: Date
    public var panoId: String
    public var location: PanoramaLocation
    public var requestedLocation: PanoramaLocation
    public var sceneKind: SearchSceneKind?
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
    public var selectionReasonSummary: String?
    public var selectionReasonDetails: [String]?

    public init(id: UUID = UUID(), visitedAt: Date = Date(), panorama: Panorama) {
        self.id = id
        self.visitedAt = visitedAt
        self.panoId = panorama.panoId
        self.location = panorama.location
        self.requestedLocation = panorama.requestedLocation
        self.sceneKind = panorama.sceneKind
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
        self.selectionReasonSummary = panorama.selectionReasonSummary
        self.selectionReasonDetails = panorama.selectionReasonDetails
    }

    public var panorama: Panorama {
        Panorama(
            panoId: panoId,
            location: location,
            requestedLocation: requestedLocation,
            sceneKind: sceneKind,
            heading: heading,
            pitch: pitch,
            fov: fov,
            date: date,
            copyright: copyright,
            areaLabel: areaLabel,
            scopeLabel: scopeLabel,
            continentLabel: continentLabel,
            countryLabel: countryLabel,
            attempts: attempts,
            selectionReasonSummary: selectionReasonSummary,
            selectionReasonDetails: selectionReasonDetails
        )
    }
}

public enum PlaceFeedbackKind: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case liked
    case tooSimilar
    case tooManyRoads
    case moreCity

    public var label: String {
        switch self {
        case .liked:
            "Liked"
        case .tooSimilar:
            "Too similar"
        case .tooManyRoads:
            "Too many roads"
        case .moreCity:
            "More city"
        }
    }
}

public struct PlaceFeedbackEntry: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var kind: PlaceFeedbackKind
    public var panoId: String?
    public var location: PanoramaLocation?
    public var sceneKind: SearchSceneKind?
    public var countryLabel: String?
    public var continentLabel: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: PlaceFeedbackKind,
        panorama: Panorama?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.panoId = panorama?.panoId
        self.location = panorama?.location
        self.sceneKind = panorama?.sceneKind
        self.countryLabel = panorama?.countryLabel
        self.continentLabel = panorama?.continentLabel
    }
}

public struct FeedbackSummary: Equatable, Sendable {
    public var recent: [PlaceFeedbackEntry]
    public var all: [PlaceFeedbackEntry]

    public init(recent: [PlaceFeedbackEntry] = [], all: [PlaceFeedbackEntry] = []) {
        self.recent = recent
        self.all = all
    }

    public func recentCount(_ kind: PlaceFeedbackKind) -> Int {
        recent.filter { $0.kind == kind }.count
    }

    public func totalCount(_ kind: PlaceFeedbackKind) -> Int {
        all.filter { $0.kind == kind }.count
    }

    public func recentLikedSceneCount(_ sceneKind: SearchSceneKind) -> Int {
        recent.filter { $0.kind == .liked && $0.sceneKind == sceneKind }.count
    }
}

public struct SamplerConfig: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var source: String?
    public var targetCityShare: Double
    public var minimumWeightMultiplier: Double
    public var recentScenePenalty: Double
    public var recentCountryPenalty: Double
    public var recentContinentPenalty: Double
    public var recentDensityPenalty: Double
    public var nonCityClusterPenalty: Double
    public var longTermExplorationBoost: Double
    public var feedbackInfluence: Double
    public var sceneMultipliers: [String: Double]
    public var countryMultipliers: [String: Double]
    public var continentMultipliers: [String: Double]

    public init(
        schemaVersion: Int = 1,
        source: String? = nil,
        targetCityShare: Double = 0.35,
        minimumWeightMultiplier: Double = 0.08,
        recentScenePenalty: Double = 1.25,
        recentCountryPenalty: Double = 1.15,
        recentContinentPenalty: Double = 0.55,
        recentDensityPenalty: Double = 0.85,
        nonCityClusterPenalty: Double = 1.65,
        longTermExplorationBoost: Double = 0.35,
        feedbackInfluence: Double = 0.25,
        sceneMultipliers: [String: Double] = [:],
        countryMultipliers: [String: Double] = [:],
        continentMultipliers: [String: Double] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.targetCityShare = targetCityShare
        self.minimumWeightMultiplier = minimumWeightMultiplier
        self.recentScenePenalty = recentScenePenalty
        self.recentCountryPenalty = recentCountryPenalty
        self.recentContinentPenalty = recentContinentPenalty
        self.recentDensityPenalty = recentDensityPenalty
        self.nonCityClusterPenalty = nonCityClusterPenalty
        self.longTermExplorationBoost = longTermExplorationBoost
        self.feedbackInfluence = feedbackInfluence
        self.sceneMultipliers = sceneMultipliers
        self.countryMultipliers = countryMultipliers
        self.continentMultipliers = continentMultipliers
    }

    public static let `default` = SamplerConfig()
}

public struct SamplingDiversityContext: Equatable, Sendable {
    public var recentHistory: [HistoryEntry]
    public var allHistory: [HistoryEntry]
    public var recentContinents: [String]
    public var recentCountries: [String]
    public var recentDensityTiers: [SearchDensityTier]
    public var recentSceneKinds: [SearchSceneKind]
    public var feedback: FeedbackSummary
    public var config: SamplerConfig

    public init(
        recentHistory: [HistoryEntry] = [],
        allHistory: [HistoryEntry] = [],
        recentContinents: [String] = [],
        recentCountries: [String] = [],
        recentDensityTiers: [SearchDensityTier] = [],
        recentSceneKinds: [SearchSceneKind] = [],
        feedback: FeedbackSummary = FeedbackSummary(),
        config: SamplerConfig = .default
    ) {
        self.recentHistory = recentHistory
        self.allHistory = allHistory
        self.recentContinents = recentContinents
        self.recentCountries = recentCountries
        self.recentDensityTiers = recentDensityTiers
        self.recentSceneKinds = recentSceneKinds
        self.feedback = feedback
        self.config = config
    }

    public static let empty = SamplingDiversityContext()

    public func withLegacySignals(
        recentContinents legacyContinents: [String],
        recentCountries legacyCountries: [String],
        recentDensityTiers legacyDensityTiers: [SearchDensityTier],
        recentSceneKinds legacySceneKinds: [SearchSceneKind]
    ) -> SamplingDiversityContext {
        SamplingDiversityContext(
            recentHistory: recentHistory,
            allHistory: allHistory,
            recentContinents: recentContinents.isEmpty ? legacyContinents : recentContinents,
            recentCountries: recentCountries.isEmpty ? legacyCountries : recentCountries,
            recentDensityTiers: recentDensityTiers.isEmpty ? legacyDensityTiers : recentDensityTiers,
            recentSceneKinds: recentSceneKinds.isEmpty ? legacySceneKinds : recentSceneKinds,
            feedback: feedback,
            config: config
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
