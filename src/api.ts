import type { ApiError, HistoryEntry, LocationOptions, Panorama } from './types'

type RandomPanoramaScope = {
  continentId: string
  countryId: string
}

async function readApiError(response: Response) {
  try {
    const body = (await response.json()) as ApiError
    return body.details ? `${body.error}: ${body.details}` : body.error
  } catch {
    return `Request failed with ${response.status}`
  }
}

async function readJson<T>(response: Response) {
  if (!response.ok) {
    throw new Error(await readApiError(response))
  }

  return (await response.json()) as T
}

export async function fetchLocationOptions() {
  return readJson<LocationOptions>(await fetch('/api/location-options'))
}

export async function fetchHistory() {
  return readJson<HistoryEntry[]>(await fetch('/api/history'))
}

export async function fetchRandomPanorama({
  continentId,
  countryId,
}: RandomPanoramaScope) {
  const params = new URLSearchParams()

  if (continentId) {
    params.set('continent', continentId)
  }

  if (countryId) {
    params.set('country', countryId)
  }

  const queryString = params.toString()
  const url = `/api/random-panorama${queryString ? `?${queryString}` : ''}`

  return readJson<Panorama>(await fetch(url))
}
