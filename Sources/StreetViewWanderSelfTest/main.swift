import Foundation
import StreetViewWanderCore

let store = CountryDataStore()
let countries = try store.loadCountries()
guard !countries.isEmpty else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "No countries were loaded."
    ])
}

let options = try store.locationOptions()
guard !options.continents.isEmpty, !options.countries.isEmpty else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "Location options were not built."
    ])
}

func candidateForSample(
    countries: [CountryArea],
    selection: SearchSelection,
    diversityContext: SamplingDiversityContext,
    sample: Int
) throws -> SearchCandidate {
    let attempt = ((sample - 1) % SearchSampler.maxAttempts) + 1
    return try SearchSampler.pickCandidates(
        countries: countries,
        selection: selection,
        diversityContext: diversityContext,
        attempts: attempt...attempt
    )[0]
}

func sceneShare(
    _ sceneKind: SearchSceneKind,
    countries: [CountryArea],
    diversityContext: SamplingDiversityContext = .empty,
    samples: Int = 3_000
) throws -> Double {
    var count = 0
    for sample in 1...samples {
        let candidate = try candidateForSample(
            countries: countries,
            selection: SearchSelection(),
            diversityContext: diversityContext,
            sample: sample
        )
        if candidate.sceneKind == sceneKind {
            count += 1
        }
    }
    return Double(count) / Double(samples)
}

func countryShare(
    _ countryName: String,
    countries: [CountryArea],
    selection: SearchSelection,
    diversityContext: SamplingDiversityContext = .empty,
    samples: Int = 3_000
) throws -> Double {
    var count = 0
    for sample in 1...samples {
        let candidate = try candidateForSample(
            countries: countries,
            selection: selection,
            diversityContext: diversityContext,
            sample: sample
        )
        if candidate.countryLabel == countryName {
            count += 1
        }
    }
    return Double(count) / Double(samples)
}

let globalCandidate = try SearchSampler.pickCandidate(
    countries: countries,
    selection: SearchSelection()
)
guard (-90...90).contains(globalCandidate.requestedLocation.lat),
      (-180...180).contains(globalCandidate.requestedLocation.lng) else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 3, userInfo: [
        NSLocalizedDescriptionKey: "Global candidate coordinates are out of range."
    ])
}
guard globalCandidate.continentLabel != nil,
      globalCandidate.countryLabel != nil else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 4, userInfo: [
        NSLocalizedDescriptionKey: "Global candidate did not include resolved area labels."
    ])
}

let primaryContinents = ["Africa", "Asia", "Europe", "North America", "Oceania", "South America"]
var continentCounts: [String: Int] = [:]
for _ in 0..<6_000 {
    let candidate = try SearchSampler.pickCandidate(countries: countries, selection: SearchSelection())
    if let continent = candidate.continentLabel {
        continentCounts[continent, default: 0] += 1
    }
}

for continent in primaryContinents {
    let share = Double(continentCounts[continent, default: 0]) / 6_000
    guard share > 0.10, share < 0.24 else {
        throw NSError(domain: "StreetViewWanderSelfTest", code: 5, userInfo: [
            NSLocalizedDescriptionKey: "Worldwide sampling is imbalanced for \(continent): \(share)."
        ])
    }
}

let antarcticaShare = Double(continentCounts["Antarctica", default: 0]) / 6_000
guard antarcticaShare < 0.05 else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 6, userInfo: [
        NSLocalizedDescriptionKey: "Antarctica should stay rare in default worldwide sampling."
    ])
}

let europeHeavyHistory = Array(repeating: "Europe", count: 60)
var correctedEuropeCount = 0
for _ in 0..<4_000 {
    let candidate = try SearchSampler.pickCandidate(
        countries: countries,
        selection: SearchSelection(),
        recentContinents: europeHeavyHistory
    )
    if candidate.continentLabel == "Europe" {
        correctedEuropeCount += 1
    }
}

let correctedEuropeShare = Double(correctedEuropeCount) / 4_000
guard correctedEuropeShare < 0.08 else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 7, userInfo: [
        NSLocalizedDescriptionKey: "Recent-history correction did not lower Europe enough: \(correctedEuropeShare)."
    ])
}

let plannedCandidates = try SearchSampler.pickCandidates(
    countries: countries,
    selection: SearchSelection(),
    attempts: 1...40
)
guard let focusedContinent = plannedCandidates.first?.continentLabel else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 8, userInfo: [
        NSLocalizedDescriptionKey: "Planned worldwide sampling did not return a focused continent."
    ])
}

let focusedAttemptCount = focusedContinent == "Antarctica" ? 8 : 18
guard plannedCandidates.prefix(focusedAttemptCount).allSatisfy({ $0.continentLabel == focusedContinent }) else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 9, userInfo: [
        NSLocalizedDescriptionKey: "Planned worldwide sampling did not keep early retries in one continent."
    ])
}
guard plannedCandidates[focusedAttemptCount].continentLabel != focusedContinent else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 10, userInfo: [
        NSLocalizedDescriptionKey: "Planned worldwide sampling did not rotate fallback continents."
    ])
}

var radiusCounts: [Int: Int] = [:]
var sceneCounts: [SearchSceneKind: Int] = [:]
for attempt in 1...6_000 {
    let candidate = try SearchSampler.pickCandidates(
        countries: countries,
        selection: SearchSelection(),
        attempts: attempt...attempt
    )[0]
    radiusCounts[candidate.searchRadius, default: 0] += 1
    sceneCounts[candidate.sceneKind, default: 0] += 1
}

for tier in SearchDensityTier.allCases {
    let share = Double(radiusCounts[tier.searchRadius, default: 0]) / 6_000
    guard share > 0.03 else {
        throw NSError(domain: "StreetViewWanderSelfTest", code: 11, userInfo: [
            NSLocalizedDescriptionKey: "Search radius tier \(tier.rawValue) is too rare: \(share)."
        ])
    }
}

let wideRadiusShare = Double(radiusCounts[SearchDensityTier.wide.searchRadius, default: 0]) / 6_000
guard wideRadiusShare > 0.30, wideRadiusShare < 0.75 else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 12, userInfo: [
        NSLocalizedDescriptionKey: "Wide search radius should stay balanced for request efficiency and scene variety: \(wideRadiusShare)."
    ])
}

for sceneKind in SearchSceneKind.allCases {
    let share = Double(sceneCounts[sceneKind, default: 0]) / 6_000
    guard share > 0.06 else {
        throw NSError(domain: "StreetViewWanderSelfTest", code: 19, userInfo: [
            NSLocalizedDescriptionKey: "Search scene \(sceneKind.rawValue) is too rare: \(share)."
        ])
    }
}

let defaultCityShare = try sceneShare(.city, countries: countries)
guard defaultCityShare > 0.28, defaultCityShare < 0.42 else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 20, userInfo: [
        NSLocalizedDescriptionKey: "Default city share should stay near the 30-40% target: \(defaultCityShare)."
    ])
}

let baselineRoadShare = try sceneShare(.road, countries: countries)
let roadHeavyContext = SamplingDiversityContext(
    recentSceneKinds: Array(repeating: SearchSceneKind.road, count: 10)
)
let correctedRoadShare = try sceneShare(.road, countries: countries, diversityContext: roadHeavyContext)
guard correctedRoadShare < baselineRoadShare * 0.70 else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 21, userInfo: [
        NSLocalizedDescriptionKey: "Recent road repetition was not reduced enough: \(baselineRoadShare) -> \(correctedRoadShare)."
    ])
}
guard correctedRoadShare > 0.015 else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 22, userInfo: [
        NSLocalizedDescriptionKey: "Recent road repetition created a near hard ban: \(correctedRoadShare)."
    ])
}

let nonCityClusterContext = SamplingDiversityContext(
    recentSceneKinds: [.town, .road, .remote, .road, .town, .remote, .road, .town, .remote, .road]
)
let nonCityCorrectedCityShare = try sceneShare(.city, countries: countries, diversityContext: nonCityClusterContext)
guard nonCityCorrectedCityShare > defaultCityShare else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 23, userInfo: [
        NSLocalizedDescriptionKey: "Non-city cluster did not boost city variety: \(defaultCityShare) -> \(nonCityCorrectedCityShare)."
    ])
}

if let unitedStates = countries.first(where: { $0.id == "USA" }) {
    let northAmericaSelection = SearchSelection(continentId: unitedStates.continent)
    let baselineUSAShare = try countryShare(
        unitedStates.name,
        countries: countries,
        selection: northAmericaSelection
    )
    let repeatedUSAContext = SamplingDiversityContext(
        recentCountries: Array(repeating: unitedStates.name, count: 3)
    )
    let correctedUSAShare = try countryShare(
        unitedStates.name,
        countries: countries,
        selection: northAmericaSelection,
        diversityContext: repeatedUSAContext
    )
    guard correctedUSAShare < baselineUSAShare * 0.80 else {
        throw NSError(domain: "StreetViewWanderSelfTest", code: 24, userInfo: [
            NSLocalizedDescriptionKey: "Recent country repeat threshold did not reduce USA enough: \(baselineUSAShare) -> \(correctedUSAShare)."
        ])
    }
    guard correctedUSAShare > 0.01 else {
        throw NSError(domain: "StreetViewWanderSelfTest", code: 25, userInfo: [
            NSLocalizedDescriptionKey: "Recent country repeat created a near hard ban: \(correctedUSAShare)."
        ])
    }
}

let roadFeedback = (0..<6).map { _ in
    PlaceFeedbackEntry(kind: .tooManyRoads, panorama: nil)
}
let roadFeedbackContext = SamplingDiversityContext(
    feedback: FeedbackSummary(recent: roadFeedback, all: roadFeedback)
)
let roadFeedbackShare = try sceneShare(.road, countries: countries, diversityContext: roadFeedbackContext)
guard roadFeedbackShare < baselineRoadShare else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 26, userInfo: [
        NSLocalizedDescriptionKey: "Road feedback did not reduce road share: \(baselineRoadShare) -> \(roadFeedbackShare)."
    ])
}

let moreCityFeedback = (0..<6).map { _ in
    PlaceFeedbackEntry(kind: .moreCity, panorama: nil)
}
let moreCityContext = SamplingDiversityContext(
    feedback: FeedbackSummary(recent: moreCityFeedback, all: moreCityFeedback)
)
let feedbackCityShare = try sceneShare(.city, countries: countries, diversityContext: moreCityContext)
guard feedbackCityShare > defaultCityShare else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 27, userInfo: [
        NSLocalizedDescriptionKey: "More-city feedback did not increase city share: \(defaultCityShare) -> \(feedbackCityShare)."
    ])
}

let cityConfigContext = SamplingDiversityContext(
    config: SamplerConfig(sceneMultipliers: ["city": 1.8])
)
let configCityShare = try sceneShare(.city, countries: countries, diversityContext: cityConfigContext)
guard configCityShare > defaultCityShare else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 28, userInfo: [
        NSLocalizedDescriptionKey: "Sampler config scene multiplier did not affect city share: \(defaultCityShare) -> \(configCityShare)."
    ])
}

guard SearchDensityTier.classify(
    requestedLocation: PanoramaLocation(lat: 0, lng: 0),
    panoramaLocation: PanoramaLocation(lat: 0, lng: 0.001)
) == .tight,
SearchDensityTier.classify(
    requestedLocation: PanoramaLocation(lat: 0, lng: 0),
    panoramaLocation: PanoramaLocation(lat: 0, lng: 0.002)
) == .local,
SearchDensityTier.classify(
    requestedLocation: PanoramaLocation(lat: 0, lng: 0),
    panoramaLocation: PanoramaLocation(lat: 0, lng: 0.005)
) == .wide else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 13, userInfo: [
        NSLocalizedDescriptionKey: "Search density tier classification is incorrect."
    ])
}

let wideHeavyHistory = Array(repeating: SearchDensityTier.wide, count: 60)
var correctedWideCount = 0
for attempt in 1...4_000 {
    let candidate = try SearchSampler.pickCandidates(
        countries: countries,
        selection: SearchSelection(),
        recentDensityTiers: wideHeavyHistory,
        attempts: attempt...attempt
    )[0]
    if candidate.densityTier == .wide {
        correctedWideCount += 1
    }
}

let correctedWideShare = Double(correctedWideCount) / 4_000
guard correctedWideShare < 0.24 else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 14, userInfo: [
        NSLocalizedDescriptionKey: "Recent density correction did not lower wide radius enough: \(correctedWideShare)."
    ])
}

if let northAmerica = Dictionary(grouping: countries, by: \.continent)["North America"],
   let repeatedCountry = northAmerica.first {
    var baselineCount = 0
    for _ in 0..<4_000 {
        let candidate = try SearchSampler.pickCandidate(
            countries: countries,
            selection: SearchSelection(continentId: "North America")
        )
        if candidate.countryLabel == repeatedCountry.name {
            baselineCount += 1
        }
    }

    var correctedCount = 0
    let repeatedHistory = Array(repeating: repeatedCountry.name, count: 80)
    for _ in 0..<4_000 {
        let candidate = try SearchSampler.pickCandidate(
            countries: countries,
            selection: SearchSelection(continentId: "North America"),
            recentCountries: repeatedHistory
        )
        if candidate.countryLabel == repeatedCountry.name {
            correctedCount += 1
        }
    }

    guard correctedCount < baselineCount else {
        throw NSError(domain: "StreetViewWanderSelfTest", code: 15, userInfo: [
            NSLocalizedDescriptionKey: "Recent country correction did not lower repeated country sampling."
        ])
    }
}

if let firstCountry = options.countries.first {
    let countryCandidate = try SearchSampler.pickCandidate(
        countries: countries,
        selection: SearchSelection(continentId: firstCountry.continent, countryId: firstCountry.id)
    )
    guard countryCandidate.countryLabel == firstCountry.label else {
        throw NSError(domain: "StreetViewWanderSelfTest", code: 16, userInfo: [
            NSLocalizedDescriptionKey: "Country-scoped sampling returned the wrong country."
        ])
    }

    let oceanLocation = PanoramaLocation(lat: 0, lng: 0)
    let resolvedCountryCandidate = SearchSampler.resolveCandidate(
        countryCandidate,
        for: oceanLocation,
        countries: countries,
        selection: SearchSelection(continentId: firstCountry.continent, countryId: firstCountry.id)
    )
    guard resolvedCountryCandidate == nil else {
        throw NSError(domain: "StreetViewWanderSelfTest", code: 17, userInfo: [
            NSLocalizedDescriptionKey: "Country-scoped sampling accepted a panorama outside known country bounds."
        ])
    }
}

let env = EnvFile.parse(
    """
    VITE_GOOGLE_MAPS_API_KEY=browser
    GOOGLE_STREET_VIEW_METADATA_API_KEY='metadata'
    """
)
guard env["VITE_GOOGLE_MAPS_API_KEY"] == "browser",
      env["GOOGLE_STREET_VIEW_METADATA_API_KEY"] == "metadata" else {
    throw NSError(domain: "StreetViewWanderSelfTest", code: 18, userInfo: [
        NSLocalizedDescriptionKey: ".env parsing failed."
    ])
}

print("StreetViewWanderSelfTest passed: \(countries.count) countries, \(options.continents.count) continents.")
