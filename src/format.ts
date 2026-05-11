import type { Panorama } from './types'

export function formatCoord(value: number) {
  return value.toFixed(6)
}

export function formatVisitedAt(value: string) {
  const date = new Date(value)

  if (Number.isNaN(date.getTime())) {
    return value
  }

  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date)
}

export function buildMapsLink(panorama: Panorama) {
  const params = new URLSearchParams({
    api: '1',
    query: `${panorama.location.lat},${panorama.location.lng}`,
  })

  return `https://www.google.com/maps/search/?${params.toString()}`
}
