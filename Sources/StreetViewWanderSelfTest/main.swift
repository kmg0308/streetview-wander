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

let focusedAttemptCount = focusedContinent == "Antarctica" ? 8 : 36
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

if let firstCountry = options.countries.first {
    let countryCandidate = try SearchSampler.pickCandidate(
        countries: countries,
        selection: SearchSelection(continentId: firstCountry.continent, countryId: firstCountry.id)
    )
    guard countryCandidate.countryLabel == firstCountry.label else {
        throw NSError(domain: "StreetViewWanderSelfTest", code: 11, userInfo: [
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
        throw NSError(domain: "StreetViewWanderSelfTest", code: 12, userInfo: [
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
    throw NSError(domain: "StreetViewWanderSelfTest", code: 13, userInfo: [
        NSLocalizedDescriptionKey: ".env parsing failed."
    ])
}

print("StreetViewWanderSelfTest passed: \(countries.count) countries, \(options.continents.count) continents.")
