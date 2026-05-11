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

if let firstCountry = options.countries.first {
    let countryCandidate = try SearchSampler.pickCandidate(
        countries: countries,
        selection: SearchSelection(continentId: firstCountry.continent, countryId: firstCountry.id)
    )
    guard countryCandidate.countryLabel == firstCountry.label else {
        throw NSError(domain: "StreetViewWanderSelfTest", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "Country-scoped sampling returned the wrong country."
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
    throw NSError(domain: "StreetViewWanderSelfTest", code: 5, userInfo: [
        NSLocalizedDescriptionKey: ".env parsing failed."
    ])
}

print("StreetViewWanderSelfTest passed: \(countries.count) countries, \(options.continents.count) continents.")
