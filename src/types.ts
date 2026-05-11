export type PanoramaLocation = {
  lat: number
  lng: number
}

export type Panorama = {
  panoId: string
  location: PanoramaLocation
  requestedLocation: PanoramaLocation
  heading: number
  pitch: number
  fov: number
  date?: string
  copyright?: string
  areaLabel: string
  scopeLabel?: string
  continentLabel?: string
  countryLabel?: string
  attempts: number
}

export type HistoryEntry = Panorama & {
  id: string
  visitedAt: string
}

export type ContinentOption = {
  id: string
  label: string
  countryCount: number
}

export type CountryOption = {
  id: string
  code: string
  label: string
  continent: string
  subregion: string
}

export type LocationOptions = {
  continents: ContinentOption[]
  countries: CountryOption[]
}

export type ApiError = {
  error: string
  details?: string
}
