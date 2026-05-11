import { useEffect, useRef, useState } from 'react'
import {
  googleMapsKey,
  loadGoogleMaps,
  type GoogleMapInstance,
} from '../googleMaps'
import type { PanoramaLocation } from '../types'

export function MiniMap({ location }: { location: PanoramaLocation | null }) {
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
