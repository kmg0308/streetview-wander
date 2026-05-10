import { useCallback, useEffect, useRef, useState } from 'react'
import './App.css'

type PanoramaLocation = {
  lat: number
  lng: number
}

type Panorama = {
  panoId: string
  location: PanoramaLocation
  requestedLocation: PanoramaLocation
  heading: number
  pitch: number
  fov: number
  date?: string
  copyright?: string
  areaLabel: string
  attempts: number
}

type HistoryEntry = Panorama & {
  id: string
  visitedAt: string
}

type ApiError = {
  error: string
  details?: string
}

type PanelMode = 'details' | 'history' | null

type GoogleMapOptions = {
  center: PanoramaLocation
  zoom: number
  mapTypeId: string
  disableDefaultUI: boolean
  clickableIcons: boolean
  keyboardShortcuts: boolean
  scrollwheel: boolean
  gestureHandling: string
}

type GoogleStreetViewPov = {
  heading: number
  pitch: number
}

type GoogleStreetViewPanoramaOptions = {
  pano: string
  pov: GoogleStreetViewPov
  zoom: number
  visible: boolean
  addressControl: boolean
  clickToGo: boolean
  enableCloseButton: boolean
  fullscreenControl: boolean
  linksControl: boolean
  motionTrackingControl: boolean
  panControl: boolean
  showRoadLabels: boolean
  zoomControl: boolean
}

type GoogleMapInstance = {
  setCenter: (location: PanoramaLocation) => void
  setZoom: (zoom: number) => void
}

type GoogleStreetViewPanoramaInstance = {
  setPano: (panoId: string) => void
  setPov: (pov: GoogleStreetViewPov) => void
  setVisible: (isVisible: boolean) => void
  setZoom: (zoom: number) => void
}

type GoogleMapsGlobal = {
  maps: {
    Map: new (element: HTMLElement, options: GoogleMapOptions) => GoogleMapInstance
    StreetViewPanorama: new (
      element: HTMLElement,
      options: GoogleStreetViewPanoramaOptions,
    ) => GoogleStreetViewPanoramaInstance
  }
}

declare global {
  interface Window {
    google?: GoogleMapsGlobal
    __streetViewWanderMapsPromise?: Promise<GoogleMapsGlobal>
    __streetViewWanderMapsReady?: () => void
  }
}

const googleMapsKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY as
  | string
  | undefined

function formatCoord(value: number) {
  return value.toFixed(6)
}

function formatVisitedAt(value: string) {
  const date = new Date(value)

  if (Number.isNaN(date.getTime())) {
    return value
  }

  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date)
}

function buildMapsLink(panorama: Panorama) {
  const params = new URLSearchParams({
    api: '1',
    query: `${panorama.location.lat},${panorama.location.lng}`,
  })

  return `https://www.google.com/maps/search/?${params.toString()}`
}

async function readApiError(response: Response) {
  try {
    const body = (await response.json()) as ApiError
    return body.details ? `${body.error}: ${body.details}` : body.error
  } catch {
    return `Request failed with ${response.status}`
  }
}

function loadGoogleMaps(apiKey: string) {
  if (window.google?.maps.Map && window.google.maps.StreetViewPanorama) {
    return Promise.resolve(window.google)
  }

  if (!window.__streetViewWanderMapsPromise) {
    window.__streetViewWanderMapsPromise = new Promise((resolve, reject) => {
      const existingScript = document.querySelector<HTMLScriptElement>(
        'script[data-streetview-wander-map]',
      )

      if (existingScript) {
        existingScript.addEventListener('load', () => {
          if (window.google?.maps.Map && window.google.maps.StreetViewPanorama) {
            resolve(window.google)
          } else {
            reject(new Error('Google Maps did not initialize.'))
          }
        })
        existingScript.addEventListener('error', () => {
          reject(new Error('Could not load Google Maps.'))
        })
        return
      }

      const params = new URLSearchParams({
        key: apiKey,
        v: 'weekly',
        loading: 'async',
        callback: '__streetViewWanderMapsReady',
      })
      const script = document.createElement('script')
      script.src = `https://maps.googleapis.com/maps/api/js?${params.toString()}`
      script.async = true
      script.defer = true
      script.dataset.streetviewWanderMap = 'true'
      window.__streetViewWanderMapsReady = () => {
        if (window.google?.maps.Map && window.google.maps.StreetViewPanorama) {
          resolve(window.google)
        } else {
          reject(new Error('Google Maps did not initialize.'))
        }
      }
      script.addEventListener('error', () => {
        reject(new Error('Could not load Google Maps.'))
      })
      document.head.append(script)
    })
  }

  return window.__streetViewWanderMapsPromise
}

function getStreetViewZoom(fov: number) {
  const zoom = Math.round(Math.log2(180 / fov))
  return Math.max(0, Math.min(4, zoom))
}

function StreetViewPane({ panorama }: { panorama: Panorama | null }) {
  const panoramaElementRef = useRef<HTMLDivElement | null>(null)
  const panoramaRef = useRef<GoogleStreetViewPanoramaInstance | null>(null)
  const [viewError, setViewError] = useState<string | null>(null)

  useEffect(() => {
    if (!googleMapsKey || !panorama || !panoramaElementRef.current) {
      return
    }

    let isCancelled = false
    const pov = {
      heading: panorama.heading,
      pitch: panorama.pitch,
    }
    const zoom = getStreetViewZoom(panorama.fov)

    void loadGoogleMaps(googleMapsKey)
      .then((google) => {
        if (isCancelled || !panoramaElementRef.current) {
          return
        }

        if (!panoramaRef.current) {
          panoramaRef.current = new google.maps.StreetViewPanorama(
            panoramaElementRef.current,
            {
              pano: panorama.panoId,
              pov,
              zoom,
              visible: true,
              addressControl: true,
              clickToGo: true,
              enableCloseButton: false,
              fullscreenControl: false,
              linksControl: true,
              motionTrackingControl: false,
              panControl: false,
              showRoadLabels: true,
              zoomControl: false,
            },
          )
        } else {
          panoramaRef.current.setPano(panorama.panoId)
          panoramaRef.current.setPov(pov)
          panoramaRef.current.setZoom(zoom)
          panoramaRef.current.setVisible(true)
        }

        setViewError(null)
      })
      .catch((caughtError: unknown) => {
        const message =
          caughtError instanceof Error
            ? caughtError.message
            : 'Could not load Google Street View.'
        setViewError(message)
      })

    return () => {
      isCancelled = true
    }
  }, [panorama])

  if (!panorama) {
    return <div className="empty-state">Street View will appear here.</div>
  }

  return (
    <>
      <div ref={panoramaElementRef} className="street-view-canvas" />
      {viewError ? <div className="street-view-error">{viewError}</div> : null}
    </>
  )
}

function MiniMap({ location }: { location: PanoramaLocation | null }) {
  const mapElementRef = useRef<HTMLDivElement | null>(null)
  const mapRef = useRef<GoogleMapInstance | null>(null)
  const [mapError, setMapError] = useState<string | null>(null)

  useEffect(() => {
    if (!googleMapsKey || !location || !mapElementRef.current) {
      return
    }

    let isCancelled = false

    void loadGoogleMaps(googleMapsKey)
      .then((google) => {
        if (isCancelled || !mapElementRef.current) {
          return
        }

        if (!mapRef.current) {
          mapRef.current = new google.maps.Map(mapElementRef.current, {
            center: location,
            zoom: 15,
            mapTypeId: 'roadmap',
            disableDefaultUI: true,
            clickableIcons: false,
            keyboardShortcuts: false,
            scrollwheel: true,
            gestureHandling: 'greedy',
          })
        } else {
          mapRef.current.setCenter(location)
          mapRef.current.setZoom(15)
        }

        setMapError(null)
      })
      .catch((caughtError: unknown) => {
        const message =
          caughtError instanceof Error
            ? caughtError.message
            : 'Could not load Google Maps.'
        setMapError(message)
      })

    return () => {
      isCancelled = true
    }
  }, [location])

  if (!location) {
    return <div className="empty-state">Map will appear here.</div>
  }

  return (
    <div className="map-shell">
      <div ref={mapElementRef} className="google-map" />
      <div className="map-center-pin" aria-hidden="true" />
      {mapError ? <div className="map-error">{mapError}</div> : null}
    </div>
  )
}

function App() {
  const [panorama, setPanorama] = useState<Panorama | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [historyError, setHistoryError] = useState<string | null>(null)
  const [historyEntries, setHistoryEntries] = useState<HistoryEntry[]>([])
  const [isLoading, setIsLoading] = useState(false)
  const [activePanel, setActivePanel] = useState<PanelMode>(null)
  const [isMapExpanded, setIsMapExpanded] = useState(true)

  const canRenderMaps = Boolean(googleMapsKey)

  const isDetailsOpen = activePanel === 'details'
  const isHistoryOpen = activePanel === 'history'

  const loadHistory = useCallback(async () => {
    try {
      const response = await fetch('/api/history')

      if (!response.ok) {
        throw new Error(await readApiError(response))
      }

      const nextHistory = (await response.json()) as HistoryEntry[]
      setHistoryEntries(nextHistory)
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
      const response = await fetch('/api/random-panorama')

      if (!response.ok) {
        throw new Error(await readApiError(response))
      }

      const nextPanorama = (await response.json()) as Panorama
      setPanorama(nextPanorama)
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
  }, [loadHistory])

  const placeDetails = panorama ? (
    <>
      <dl>
        <div>
          <dt>Area</dt>
          <dd>{panorama.areaLabel}</dd>
        </div>
        <div>
          <dt>Latitude</dt>
          <dd>{formatCoord(panorama.location.lat)}</dd>
        </div>
        <div>
          <dt>Longitude</dt>
          <dd>{formatCoord(panorama.location.lng)}</dd>
        </div>
        <div>
          <dt>Attempts</dt>
          <dd>{panorama.attempts}</dd>
        </div>
        {panorama.date ? (
          <div>
            <dt>Image date</dt>
            <dd>{panorama.date}</dd>
          </div>
        ) : null}
      </dl>

      <a
        className="secondary-action"
        href={buildMapsLink(panorama)}
        target="_blank"
        rel="noreferrer"
      >
        Open in Google Maps
      </a>
    </>
  ) : (
    <p className="muted">Pick a random place to begin.</p>
  )

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
          className="primary-action"
          onClick={() => void loadRandomPanorama()}
          disabled={isLoading}
        >
          {isLoading ? 'Finding...' : 'Random place'}
        </button>
      </div>

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
        <aside
          className={`floating-map${isMapExpanded ? '' : ' is-collapsed'}`}
          aria-label="Floating map"
        >
          <button
            type="button"
            className="map-toggle"
            aria-controls="floating-map-body"
            aria-expanded={isMapExpanded}
            onClick={() => setIsMapExpanded((currentValue) => !currentValue)}
          >
            {isMapExpanded ? 'Hide map' : 'Map'}
          </button>
          <div
            id="floating-map-body"
            className="floating-map-body"
            aria-hidden={!isMapExpanded}
          >
            <MiniMap location={panorama.location} />
          </div>
        </aside>
      ) : null}

      {isDetailsOpen ? (
        <aside className="details-panel" aria-label="Current location details">
          <header className="details-panel-header">
            <h2>Current start point</h2>
          </header>

          <div className="place-details">
            {placeDetails}
          </div>
        </aside>
      ) : null}

      {isHistoryOpen ? (
        <aside className="details-panel history-panel" aria-label="Visit history">
          <header className="details-panel-header history-panel-header">
            <h2>Visit history</h2>
            <span>{historyEntries.length}</span>
          </header>

          <div className="history-content">
            {historyError ? (
              <p className="history-error">{historyError}</p>
            ) : null}

            {!historyError && historyEntries.length === 0 ? (
              <p className="muted">No random places yet.</p>
            ) : null}

            {historyEntries.length > 0 ? (
              <ul className="history-list">
                {historyEntries.map((entry) => (
                  <li className="history-item" key={entry.id}>
                    <div className="history-item-header">
                      <strong>{entry.areaLabel}</strong>
                      <time dateTime={entry.visitedAt}>
                        {formatVisitedAt(entry.visitedAt)}
                      </time>
                    </div>

                    <div className="history-coordinates">
                      {formatCoord(entry.location.lat)},{' '}
                      {formatCoord(entry.location.lng)}
                    </div>

                    <div className="history-meta">
                      {entry.date ? `Image date ${entry.date}` : 'Image date unknown'}
                      {' · '}
                      {entry.attempts} {entry.attempts === 1 ? 'try' : 'tries'}
                    </div>

                    <div className="history-actions">
                      <button
                        type="button"
                        className="compact-action"
                        onClick={() => {
                          setPanorama(entry)
                          setActivePanel(null)
                        }}
                      >
                        Revisit
                      </button>
                      <a
                        className="compact-action compact-link"
                        href={buildMapsLink(entry)}
                        target="_blank"
                        rel="noreferrer"
                      >
                        Open Maps
                      </a>
                    </div>
                  </li>
                ))}
              </ul>
            ) : null}
          </div>
        </aside>
      ) : null}
    </main>
  )
}

export default App
