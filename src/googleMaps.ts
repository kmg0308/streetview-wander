import type { PanoramaLocation } from './types'

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

export type GoogleStreetViewPov = {
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

export type GoogleMapInstance = {
  setCenter: (location: PanoramaLocation) => void
  setZoom: (zoom: number) => void
}

export type GoogleStreetViewPanoramaInstance = {
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

export const googleMapsKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY as
  | string
  | undefined

export function loadGoogleMaps(apiKey: string) {
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

export function getStreetViewZoom(fov: number) {
  const zoom = Math.round(Math.log2(180 / fov))
  return Math.max(0, Math.min(4, zoom))
}
