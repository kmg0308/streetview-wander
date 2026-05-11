import { buildMapsLink, formatCoord } from '../format'
import type { Panorama } from '../types'

export function DetailsPanel({ panorama }: { panorama: Panorama | null }) {
  const placeDetails = panorama ? (
    <>
      <dl>
        <div>
          <dt>Scope</dt>
          <dd>{panorama.scopeLabel ?? 'World'}</dd>
        </div>
        <div>
          <dt>Area</dt>
          <dd>{panorama.areaLabel}</dd>
        </div>
        {panorama.countryLabel ? (
          <div>
            <dt>Country</dt>
            <dd>{panorama.countryLabel}</dd>
          </div>
        ) : null}
        {panorama.continentLabel ? (
          <div>
            <dt>Continent</dt>
            <dd>{panorama.continentLabel}</dd>
          </div>
        ) : null}
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
    <aside className="details-panel" aria-label="Current location details">
      <header className="details-panel-header">
        <h2>Current start point</h2>
      </header>

      <div className="place-details">{placeDetails}</div>
    </aside>
  )
}
