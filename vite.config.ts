import type { ServerResponse } from 'node:http'
import type { Plugin } from 'vite'
import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'

type Bounds = {
  label: string
  north: number
  south: number
  east: number
  west: number
}

type PanoramaMetadata = {
  status: string
  pano_id?: string
  location?: {
    lat: number
    lng: number
  }
  date?: string
  copyright?: string
  error_message?: string
}

const SEARCH_AREAS: Bounds[] = [
  {
    label: 'United States',
    north: 48.9,
    south: 25.0,
    east: -66.8,
    west: -124.8,
  },
  {
    label: 'Western Europe',
    north: 58.0,
    south: 36.0,
    east: 18.0,
    west: -9.8,
  },
  {
    label: 'Japan and Korea',
    north: 45.7,
    south: 31.0,
    east: 145.8,
    west: 126.0,
  },
  {
    label: 'Australia and New Zealand',
    north: -10.0,
    south: -46.8,
    east: 178.8,
    west: 112.8,
  },
  {
    label: 'South America',
    north: 5.0,
    south: -45.0,
    east: -34.0,
    west: -76.0,
  },
  {
    label: 'Southern Africa',
    north: -17.0,
    south: -35.0,
    east: 33.0,
    west: 16.0,
  },
]

const MAX_ATTEMPTS = 45

function randomInRange(min: number, max: number) {
  return min + Math.random() * (max - min)
}

function pickSearchArea() {
  return SEARCH_AREAS[Math.floor(Math.random() * SEARCH_AREAS.length)]
}

function pickPoint(bounds: Bounds) {
  return {
    lat: randomInRange(bounds.south, bounds.north),
    lng: randomInRange(bounds.west, bounds.east),
  }
}

function sendJson(response: ServerResponse, statusCode: number, body: unknown) {
  response.statusCode = statusCode
  response.setHeader('Content-Type', 'application/json')
  response.end(JSON.stringify(body))
}

async function getMetadata(apiKey: string, location: { lat: number; lng: number }) {
  const params = new URLSearchParams({
    key: apiKey,
    location: `${location.lat},${location.lng}`,
    radius: '800',
    source: 'outdoor',
  })
  const response = await fetch(
    `https://maps.googleapis.com/maps/api/streetview/metadata?${params.toString()}`,
  )

  if (!response.ok) {
    throw new Error(`Google metadata request failed with ${response.status}`)
  }

  return (await response.json()) as PanoramaMetadata
}

async function findRandomPanorama(apiKey: string) {
  let lastStatus = 'NO_ATTEMPTS'

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    const area = pickSearchArea()
    const requestedLocation = pickPoint(area)
    const metadata = await getMetadata(apiKey, requestedLocation)

    lastStatus = metadata.error_message ?? metadata.status

    if (metadata.status === 'OK' && metadata.location && metadata.pano_id) {
      return {
        panoId: metadata.pano_id,
        location: metadata.location,
        requestedLocation,
        heading: Math.floor(Math.random() * 360),
        pitch: 0,
        fov: 85,
        date: metadata.date,
        copyright: metadata.copyright,
        areaLabel: area.label,
        attempts: attempt,
      }
    }
  }

  throw new Error(`No panorama found after ${MAX_ATTEMPTS} tries. Last status: ${lastStatus}`)
}

function randomStreetViewApi(): Plugin {
  return {
    name: 'random-street-view-api',
    configureServer(server) {
      const env = loadEnv(server.config.mode, server.config.root, '')
      const apiKey =
        env.GOOGLE_STREET_VIEW_METADATA_API_KEY ?? env.GOOGLE_MAPS_API_KEY

      server.middlewares.use('/api/random-panorama', async (request, response) => {
        if (request.method !== 'GET') {
          sendJson(response, 405, { error: 'Only GET is supported.' })
          return
        }

        if (!apiKey) {
          sendJson(response, 500, {
            error: 'Missing GOOGLE_STREET_VIEW_METADATA_API_KEY in .env.',
          })
          return
        }

        try {
          sendJson(response, 200, await findRandomPanorama(apiKey))
        } catch (error) {
          sendJson(response, 502, {
            error: 'Could not find a usable Street View panorama.',
            details: error instanceof Error ? error.message : String(error),
          })
        }
      })
    },
  }
}

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), randomStreetViewApi()],
})
