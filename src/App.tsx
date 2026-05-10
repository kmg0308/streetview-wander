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

const embedKey = import.meta.env.VITE_GOOGLE_MAPS_EMBED_API_KEY as
  | string
  | undefined

function formatCoord(value: number) {
  return value.toFixed(6)
}

function buildStreetViewUrl(panorama: Panorama) {
  const params = new URLSearchParams({
    key: embedKey ?? '',
    location: `${panorama.location.lat},${panorama.location.lng}`,
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

  return (
    <main className="app-shell">
      <header className="top-bar">
        <div>
          <p className="eyebrow">Local Street View explorer</p>
          <h1>StreetView Wander</h1>
        </div>

        <button
          type="button"
          className="primary-action"
          onClick={() => void loadRandomPanorama()}
          disabled={isLoading}
        >
          {isLoading ? 'Finding...' : 'Random place'}
        </button>
      </header>

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

      <section className="viewer-grid">
        <div className="viewer-pane street-view-pane">
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
        </div>

        <aside className="map-side">
          <div className="viewer-pane map-pane">
            {mapUrl ? (
              <iframe
                title="Google Map for current Street View"
                src={mapUrl}
                allowFullScreen
                loading="eager"
                referrerPolicy="no-referrer-when-downgrade"
              />
            ) : (
              <div className="empty-state">Map will appear here.</div>
            )}
          </div>

          <div className="place-details">
            <h2>Current start point</h2>
            {panorama ? (
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
            )}
          </div>
        </aside>
      </section>
    </main>
  )
}

export default App
