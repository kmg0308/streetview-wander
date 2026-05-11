import { useCallback, useEffect, useState } from 'react'
import {
  fetchHistory,
  fetchLocationOptions,
  fetchRandomPanorama,
} from './api'
import './App.css'
import { DetailsPanel } from './components/DetailsPanel'
import { FloatingMap } from './components/FloatingMap'
import { HistoryPanel } from './components/HistoryPanel'
import { LocationFilter } from './components/LocationFilter'
import { StreetViewPane } from './components/StreetViewPane'
import { googleMapsKey } from './googleMaps'
import type { HistoryEntry, LocationOptions, Panorama } from './types'

type PanelMode = 'details' | 'history' | null

function findOptionByLabel<T extends { id: string; label: string }>(
  options: T[],
  value: string,
) {
  const normalizedValue = value.trim().toLocaleLowerCase()

  if (!normalizedValue) {
    return null
  }

  return (
    options.find(
      (option) =>
        option.label.toLocaleLowerCase() === normalizedValue ||
        option.id.toLocaleLowerCase() === normalizedValue,
    ) ?? null
  )
}

function App() {
  const [panorama, setPanorama] = useState<Panorama | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [historyError, setHistoryError] = useState<string | null>(null)
  const [historyEntries, setHistoryEntries] = useState<HistoryEntry[]>([])
  const [locationOptions, setLocationOptions] = useState<LocationOptions>({
    continents: [],
    countries: [],
  })
  const [locationOptionsError, setLocationOptionsError] = useState<string | null>(
    null,
  )
  const [selectedContinentId, setSelectedContinentId] = useState('')
  const [selectedCountryId, setSelectedCountryId] = useState('')
  const [continentInput, setContinentInput] = useState('')
  const [countryInput, setCountryInput] = useState('')
  const [isLoading, setIsLoading] = useState(false)
  const [activePanel, setActivePanel] = useState<PanelMode>(null)
  const [isMapExpanded, setIsMapExpanded] = useState(true)
  const [isScopePanelOpen, setIsScopePanelOpen] = useState(false)

  const canRenderMaps = Boolean(googleMapsKey)

  const isDetailsOpen = activePanel === 'details'
  const isHistoryOpen = activePanel === 'history'
  const countryOptions = selectedContinentId
    ? locationOptions.countries.filter(
        (country) => country.continent === selectedContinentId,
      )
    : locationOptions.countries
  const selectedContinent = locationOptions.continents.find(
    (continent) => continent.id === selectedContinentId,
  )
  const selectedCountry = locationOptions.countries.find(
    (country) => country.id === selectedCountryId,
  )
  const selectedScopeLabel =
    selectedCountry?.label ?? selectedContinent?.label ?? 'Worldwide'

  useEffect(() => {
    let isCancelled = false

    void fetchLocationOptions()
      .then((nextLocationOptions) => {
        if (isCancelled) {
          return
        }

        setLocationOptions(nextLocationOptions)
        setLocationOptionsError(null)
      })
      .catch((caughtError: unknown) => {
        if (isCancelled) {
          return
        }

        const message =
          caughtError instanceof Error
            ? caughtError.message
            : 'Could not load location filters.'
        setLocationOptionsError(message)
      })

    return () => {
      isCancelled = true
    }
  }, [])

  const clearContinent = useCallback(() => {
    setSelectedContinentId('')
    setSelectedCountryId('')
    setContinentInput('')
    setCountryInput('')
  }, [])

  const clearCountry = useCallback(() => {
    setSelectedCountryId('')
    setCountryInput('')
  }, [])

  const updateContinentInput = useCallback(
    (nextValue: string) => {
      setContinentInput(nextValue)

      if (!nextValue.trim()) {
        setSelectedContinentId('')
        setSelectedCountryId('')
        setCountryInput('')
        return
      }

      const matchedContinent = findOptionByLabel(
        locationOptions.continents,
        nextValue,
      )

      if (!matchedContinent) {
        setSelectedContinentId('')
        setSelectedCountryId('')
        setCountryInput('')
        return
      }

      setSelectedContinentId(matchedContinent.id)

      if (selectedCountry && selectedCountry.continent !== matchedContinent.id) {
        setSelectedCountryId('')
        setCountryInput('')
      }
    },
    [locationOptions.continents, selectedCountry],
  )

  const updateCountryInput = useCallback(
    (nextValue: string) => {
      setCountryInput(nextValue)

      if (!nextValue.trim()) {
        setSelectedCountryId('')
        return
      }

      const matchedCountry = findOptionByLabel(countryOptions, nextValue)

      if (!matchedCountry) {
        setSelectedCountryId('')
        return
      }

      setSelectedCountryId(matchedCountry.id)
      setSelectedContinentId(matchedCountry.continent)
      setContinentInput(matchedCountry.continent)
      setCountryInput(matchedCountry.label)
    },
    [countryOptions],
  )

  const loadHistory = useCallback(async () => {
    try {
      setHistoryEntries(await fetchHistory())
      setHistoryError(null)
    } catch (caughtError) {
      const message =
        caughtError instanceof Error
          ? caughtError.message
          : 'Could not load local visit history.'
      setHistoryError(message)
    }
  }, [])

  const loadRandomPanorama = useCallback(async () => {
    setIsLoading(true)
    setError(null)

    try {
      const nextPanorama = await fetchRandomPanorama({
        continentId: selectedContinentId,
        countryId: selectedCountryId,
      })
      setPanorama(nextPanorama)
      setIsScopePanelOpen(false)
      void loadHistory()
    } catch (caughtError) {
      const message =
        caughtError instanceof Error
          ? caughtError.message
          : 'Could not load a random Street View location.'
      setError(message)
    } finally {
      setIsLoading(false)
    }
  }, [loadHistory, selectedContinentId, selectedCountryId])

  return (
    <main className="app-shell">
      <section className="street-view-stage" aria-label="Street View">
        {canRenderMaps ? (
          <StreetViewPane panorama={panorama} />
        ) : (
          <div className="empty-state">Street View will appear here.</div>
        )}
      </section>

      <div className="top-actions">
        <button
          type="button"
          className="details-action"
          aria-pressed={isHistoryOpen}
          onClick={() => {
            if (!isHistoryOpen) {
              void loadHistory()
            }

            setActivePanel((currentPanel) =>
              currentPanel === 'history' ? null : 'history',
            )
          }}
        >
          History
        </button>
        <button
          type="button"
          className="details-action"
          aria-pressed={isDetailsOpen}
          onClick={() =>
            setActivePanel((currentPanel) =>
              currentPanel === 'details' ? null : 'details',
            )
          }
        >
          Details
        </button>
        <button
          type="button"
          className="scope-action"
          aria-expanded={isScopePanelOpen}
          aria-controls="location-filter"
          title={`Scope: ${selectedScopeLabel}`}
          onClick={() => setIsScopePanelOpen((currentValue) => !currentValue)}
        >
          <span>Scope</span>
          <strong>{selectedScopeLabel}</strong>
        </button>
        <button
          type="button"
          className="primary-action"
          onClick={() => void loadRandomPanorama()}
          disabled={isLoading}
        >
          {isLoading ? 'Finding...' : 'Random place'}
        </button>
      </div>

      {isScopePanelOpen ? (
        <LocationFilter
          continentInput={continentInput}
          countryInput={countryInput}
          countryOptions={countryOptions}
          locationOptions={locationOptions}
          locationOptionsError={locationOptionsError}
          selectedContinentId={selectedContinentId}
          selectedCountryId={selectedCountryId}
          selectedScopeLabel={selectedScopeLabel}
          onClearContinent={clearContinent}
          onClearCountry={clearCountry}
          onClose={() => setIsScopePanelOpen(false)}
          onContinentInputChange={updateContinentInput}
          onCountryInputChange={updateCountryInput}
        />
      ) : null}

      {!canRenderMaps ? (
        <section className="setup-panel" aria-live="polite">
          <h2>Missing browser API key</h2>
          <p>
            Add <code>VITE_GOOGLE_MAPS_API_KEY</code> to your
            <code>.env</code> file, then restart the local server.
          </p>
        </section>
      ) : null}

      {error ? (
        <section className="status-panel" role="alert">
          <strong>Could not pick a location.</strong>
          <span>{error}</span>
        </section>
      ) : null}

      {panorama && canRenderMaps ? (
        <FloatingMap
          panorama={panorama}
          isExpanded={isMapExpanded}
          onToggle={() => setIsMapExpanded((currentValue) => !currentValue)}
        />
      ) : null}

      {isDetailsOpen ? <DetailsPanel panorama={panorama} /> : null}

      {isHistoryOpen ? (
        <HistoryPanel
          entries={historyEntries}
          error={historyError}
          onRevisit={(entry) => {
            setPanorama(entry)
            setActivePanel(null)
          }}
        />
      ) : null}
    </main>
  )
}

export default App
