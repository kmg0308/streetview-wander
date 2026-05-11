import type { Panorama } from '../types'
import { MiniMap } from './MiniMap'

type FloatingMapProps = {
  isExpanded: boolean
  panorama: Panorama
  onToggle: () => void
}

export function FloatingMap({
  isExpanded,
  panorama,
  onToggle,
}: FloatingMapProps) {
  return (
    <aside
      className={`floating-map${isExpanded ? '' : ' is-collapsed'}`}
      aria-label="Floating map"
    >
      <button
        type="button"
        className="map-toggle"
        aria-controls="floating-map-body"
        aria-expanded={isExpanded}
        onClick={onToggle}
      >
        {isExpanded ? 'Hide map' : 'Map'}
      </button>
      <div
        id="floating-map-body"
        className="floating-map-body"
        aria-hidden={!isExpanded}
      >
        <MiniMap location={panorama.location} />
      </div>
    </aside>
  )
}
