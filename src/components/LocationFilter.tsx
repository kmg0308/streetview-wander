import type { CountryOption, LocationOptions } from '../types'

type LocationFilterProps = {
  continentInput: string
  countryInput: string
  countryOptions: CountryOption[]
  locationOptions: LocationOptions
  locationOptionsError: string | null
  selectedContinentId: string
  selectedCountryId: string
  selectedScopeLabel: string
  onClearContinent: () => void
  onClearCountry: () => void
  onClose: () => void
  onContinentInputChange: (value: string) => void
  onCountryInputChange: (value: string) => void
}

export function LocationFilter({
  continentInput,
  countryInput,
  countryOptions,
  locationOptions,
  locationOptionsError,
  selectedContinentId,
  selectedCountryId,
  selectedScopeLabel,
  onClearContinent,
  onClearCountry,
  onClose,
  onContinentInputChange,
  onCountryInputChange,
}: LocationFilterProps) {
  return (
    <section
      id="location-filter"
      className="location-filter"
      aria-label="Random place filters"
    >
      <header className="scope-panel-header">
        <h2>Random scope</h2>
        <button type="button" className="scope-close" onClick={onClose}>
          Done
        </button>
      </header>

      <div className="scope-field">
        <label htmlFor="continent-filter">Continent</label>
        <div className="scope-input-row">
          <input
            id="continent-filter"
            type="search"
            list="continent-options"
            placeholder="Worldwide"
            value={continentInput}
            onChange={(event) => onContinentInputChange(event.target.value)}
          />
          {selectedContinentId ? (
            <button
              type="button"
              className="scope-clear"
              onClick={onClearContinent}
            >
              Clear
            </button>
          ) : null}
        </div>
        <datalist id="continent-options">
          {locationOptions.continents.map((continent) => (
            <option key={continent.id} value={continent.label} />
          ))}
        </datalist>
      </div>

      <div className="scope-field">
        <label htmlFor="country-filter">Country</label>
        <div className="scope-input-row">
          <input
            id="country-filter"
            type="search"
            list="country-options"
            placeholder="All countries"
            value={countryInput}
            onChange={(event) => onCountryInputChange(event.target.value)}
          />
          {selectedCountryId ? (
            <button type="button" className="scope-clear" onClick={onClearCountry}>
              Clear
            </button>
          ) : null}
        </div>
        <datalist id="country-options">
          {countryOptions.map((country) => (
            <option
              key={country.id}
              value={country.label}
              label={`${country.continent} · ${country.subregion}`}
            />
          ))}
        </datalist>
      </div>

      <div className="scope-current">
        {locationOptionsError ?? selectedScopeLabel}
      </div>
    </section>
  )
}
