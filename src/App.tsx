import { useCallback, useMemo, useState } from 'react'
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

type ApiError = {
  error: string
  details?: string
}

type MapMode = 'floating' | 'side' | 'hidden'

const embedKey = import.meta.env.VITE_GOOGLE_MAPS_EMBED_API_KEY as
  | string
  | undefined

function formatCoord(value: number) {
  return value.toFixed(6)
}

function buildStreetViewUrl(panorama: Panorama) {
  const params = new URLSearchParams({
    key: embedKey ?? '',
    pano: panorama.panoId,
    heading: String(panorama.heading),
    pitch: String(panorama.pitch),
    fov: String(panorama.fov),
  })

  return `https://www.google.com/maps/embed/v1/streetview?${params.toString()}`
}

function buildMapUrl(panorama: Panorama) {
  const params = new URLSearchParams({
    key: embedKey ?? '',
    center: `${panorama.location.lat},${panorama.location.lng}`,
    zoom: '15',
    maptype: 'roadmap',
  })

  return `https://www.google.com/maps/embed/v1/view?${params.toString()}`
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

function App() {
  const [panorama, setPanorama] = useState<Panorama | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(false)
  const [mapMode, setMapMode] = useState<MapMode>('floating')

  const canRenderMaps = Boolean(embedKey)

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
    } catch (caughtError) {
      const message =
        caughtError instanceof Error
          ? caughtError.message
          : 'Could not load a random Street View location.'
      setError(message)
    } finally {
      setIsLoading(false)
    }
  }, [])

  const streetViewUrl = useMemo(() => {
    if (!panorama || !canRenderMaps) {
      return null
    }

    return buildStreetViewUrl(panorama)
  }, [canRenderMaps, panorama])

  const mapUrl = useMemo(() => {
    if (!panorama || !canRenderMaps) {
      return null
    }

    return buildMapUrl(panorama)
  }, [canRenderMaps, panorama])

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

  const mapFrame = mapUrl ? (
    <iframe
      title="Google Map for current Street View"
      src={mapUrl}
      allowFullScreen
      loading="eager"
      referrerPolicy="no-referrer-when-downgrade"
    />
  ) : (
    <div className="empty-state">Map will appear here.</div>
  )

  return (
    <main className="app-shell">
      <section className="street-view-stage" aria-label="Street View">
        {streetViewUrl ? (
          <iframe
            title="Random Google Street View"
            src={streetViewUrl}
            allowFullScreen
            loading="eager"
            referrerPolicy="no-referrer-when-downgrade"
          />
        ) : (
          <div className="empty-state">Street View will appear here.</div>
        )}
      </section>

      <div className="title-chip">
        <span>StreetView Wander</span>
        {panorama ? <small>{panorama.areaLabel}</small> : null}
      </div>

      <div className="map-controls" aria-label="Map display controls">
        <button
          type="button"
          className="mode-action"
          aria-pressed={mapMode === 'floating'}
          onClick={() => setMapMode('floating')}
        >
          Map
        </button>
        <button
          type="button"
          className="mode-action"
          aria-pressed={mapMode === 'side'}
          onClick={() => setMapMode('side')}
        >
          Details
        </button>
        <button
          type="button"
          className="mode-action"
          aria-pressed={mapMode === 'hidden'}
          onClick={() => setMapMode('hidden')}
        >
          Hide
        </button>
      </div>

      <button
        type="button"
        className="primary-action"
        onClick={() => void loadRandomPanorama()}
        disabled={isLoading}
      >
        {isLoading ? 'Finding...' : 'Random place'}
      </button>

      {!canRenderMaps ? (
        <section className="setup-panel" aria-live="polite">
          <h2>Missing browser API key</h2>
          <p>
            Add <code>VITE_GOOGLE_MAPS_EMBED_API_KEY</code> to your
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

      {mapMode === 'floating' && mapUrl ? (
        <aside className="floating-map" aria-label="Floating map">
          {mapFrame}
        </aside>
      ) : null}

      {mapMode === 'side' ? (
        <aside className="side-panel" aria-label="Current location details">
          <header className="side-panel-header">
            <h2>Current start point</h2>
            <button
              type="button"
              className="plain-action"
              onClick={() => setMapMode('hidden')}
            >
              Hide
            </button>
          </header>

          <div className="panel-map">{mapFrame}</div>

          <div className="place-details">
            {placeDetails}
          </div>
        </aside>
      ) : null}
    </main>
  )
}

export default App
