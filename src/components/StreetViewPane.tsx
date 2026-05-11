import { useEffect, useRef, useState } from 'react'
import {
  getStreetViewZoom,
  googleMapsKey,
  loadGoogleMaps,
  type GoogleStreetViewPanoramaInstance,
} from '../googleMaps'
import type { Panorama } from '../types'

export function StreetViewPane({ panorama }: { panorama: Panorama | null }) {
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
