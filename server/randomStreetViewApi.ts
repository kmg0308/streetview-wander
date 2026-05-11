import { randomUUID } from 'node:crypto'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import type { ServerResponse } from 'node:http'
import { join } from 'node:path'
import type { Plugin } from 'vite'
import { loadEnv } from 'vite'

type Bounds = {
  label: string
  north: number
  south: number
  east: number
  west: number
  weight: number
}

type Coordinate = [number, number]

type CountryPart = {
  bbox: [number, number, number, number]
  weight: number
  outer: Coordinate[]
  holes: Coordinate[][]
}

type CountryArea = {
  id: string
  code: string
  name: string
  continent: string
  subregion: string
  population: number
  weight: number
  parts: CountryPart[]
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

type RandomPanorama = {
  panoId: string
  location: {
    lat: number
    lng: number
  }
  requestedLocation: {
    lat: number
    lng: number
  }
  heading: number
  pitch: number
  fov: number
  date?: string
  copyright?: string
  areaLabel: string
  scopeLabel: string
  continentLabel?: string
  countryLabel?: string
  attempts: number
}

type HistoryEntry = RandomPanorama & {
  id: string
  visitedAt: string
}

const SEARCH_AREAS: Bounds[] = [
  {
    label: 'Alaska and Yukon',
    north: 71.5,
    south: 51.0,
    east: -129.0,
    west: -170.0,
    weight: 1,
  },
  {
    label: 'Canada West',
    north: 60.0,
    south: 48.0,
    east: -95.0,
    west: -140.0,
    weight: 3,
  },
  {
    label: 'Canada East',
    north: 60.0,
    south: 42.0,
    east: -52.0,
    west: -95.0,
    weight: 3,
  },
  {
    label: 'United States',
    north: 49.5,
    south: 24.3,
    east: -66.5,
    west: -125.0,
    weight: 8,
  },
  {
    label: 'Mexico',
    north: 32.8,
    south: 14.4,
    east: -86.5,
    west: -118.5,
    weight: 5,
  },
  {
    label: 'Central America',
    north: 18.8,
    south: 7.0,
    east: -77.0,
    west: -92.5,
    weight: 2,
  },
  {
    label: 'Caribbean',
    north: 27.0,
    south: 10.0,
    east: -59.0,
    west: -86.0,
    weight: 1,
  },
  {
    label: 'Greenland and North Atlantic',
    north: 83.0,
    south: 59.0,
    east: -11.0,
    west: -74.0,
    weight: 0.5,
  },
  {
    label: 'Iceland',
    north: 66.7,
    south: 63.0,
    east: -13.0,
    west: -24.8,
    weight: 2,
  },
  {
    label: 'British Isles',
    north: 61.0,
    south: 49.5,
    east: 2.3,
    west: -10.8,
    weight: 4,
  },
  {
    label: 'Iberia',
    north: 44.2,
    south: 35.5,
    east: 4.5,
    west: -10.0,
    weight: 4,
  },
  {
    label: 'Western Europe',
    north: 51.8,
    south: 42.0,
    east: 8.5,
    west: -5.5,
    weight: 5,
  },
  {
    label: 'Central Europe',
    north: 55.2,
    south: 45.2,
    east: 20.5,
    west: 5.5,
    weight: 5,
  },
  {
    label: 'Nordics',
    north: 71.5,
    south: 54.5,
    east: 31.5,
    west: 4.0,
    weight: 4,
  },
  {
    label: 'Baltics and Poland',
    north: 59.8,
    south: 49.0,
    east: 28.5,
    west: 14.0,
    weight: 3,
  },
  {
    label: 'Italy and Malta',
    north: 47.2,
    south: 35.5,
    east: 19.0,
    west: 6.0,
    weight: 4,
  },
  {
    label: 'Balkans',
    north: 47.5,
    south: 39.0,
    east: 29.0,
    west: 13.0,
    weight: 3,
  },
  {
    label: 'Eastern Europe',
    north: 56.5,
    south: 43.0,
    east: 41.0,
    west: 20.0,
    weight: 2,
  },
  {
    label: 'Greece and Cyprus',
    north: 41.9,
    south: 34.5,
    east: 35.8,
    west: 19.0,
    weight: 3,
  },
  {
    label: 'Turkey and Caucasus',
    north: 43.8,
    south: 35.5,
    east: 50.5,
    west: 25.5,
    weight: 2,
  },
  {
    label: 'Western Russia',
    north: 68.0,
    south: 42.0,
    east: 60.0,
    west: 29.0,
    weight: 1,
  },
  {
    label: 'Middle East',
    north: 37.5,
    south: 12.0,
    east: 60.5,
    west: 34.0,
    weight: 2,
  },
  {
    label: 'Central Asia',
    north: 56.0,
    south: 35.0,
    east: 88.0,
    west: 46.0,
    weight: 1,
  },
  {
    label: 'Northern Asia West',
    north: 72.0,
    south: 50.0,
    east: 105.0,
    west: 60.0,
    weight: 0.3,
  },
  {
    label: 'Northern Asia East',
    north: 72.0,
    south: 42.0,
    east: 180.0,
    west: 105.0,
    weight: 0.3,
  },
  {
    label: 'Mongolia and Northern China',
    north: 54.0,
    south: 35.0,
    east: 125.0,
    west: 88.0,
    weight: 0.8,
  },
  {
    label: 'Eastern China',
    north: 42.5,
    south: 18.0,
    east: 124.5,
    west: 105.0,
    weight: 0.4,
  },
  {
    label: 'South Asia',
    north: 36.0,
    south: 5.0,
    east: 97.5,
    west: 66.0,
    weight: 2,
  },
  {
    label: 'Mainland Southeast Asia',
    north: 28.5,
    south: -1.5,
    east: 110.5,
    west: 92.0,
    weight: 3,
  },
  {
    label: 'Maritime Southeast Asia',
    north: 8.0,
    south: -11.0,
    east: 142.0,
    west: 95.0,
    weight: 3,
  },
  {
    label: 'Japan and Korea',
    north: 45.7,
    south: 31.0,
    east: 145.8,
    west: 126.0,
    weight: 5,
  },
  {
    label: 'Taiwan Hong Kong and Macau',
    north: 25.5,
    south: 21.8,
    east: 122.5,
    west: 113.5,
    weight: 2,
  },
  {
    label: 'Australia and New Zealand',
    north: -10.0,
    south: -46.8,
    east: 178.8,
    west: 112.8,
    weight: 5,
  },
  {
    label: 'Pacific Islands West',
    north: 16.0,
    south: -23.0,
    east: 180.0,
    west: 166.0,
    weight: 0.5,
  },
  {
    label: 'Pacific Islands East',
    north: 22.5,
    south: -25.0,
    east: -140.0,
    west: -180.0,
    weight: 0.5,
  },
  {
    label: 'Northern South America',
    north: 12.5,
    south: -8.0,
    east: -50.0,
    west: -82.0,
    weight: 3,
  },
  {
    label: 'Brazil',
    north: 6.0,
    south: -34.0,
    east: -34.0,
    west: -74.0,
    weight: 4,
  },
  {
    label: 'Andes',
    north: 5.5,
    south: -56.0,
    east: -66.0,
    west: -81.5,
    weight: 3,
  },
  {
    label: 'Southern Cone',
    north: -17.0,
    south: -56.0,
    east: -52.0,
    west: -76.0,
    weight: 3,
  },
  {
    label: 'North Africa',
    north: 37.5,
    south: 15.0,
    east: 37.0,
    west: -17.5,
    weight: 0.8,
  },
  {
    label: 'West Africa',
    north: 16.5,
    south: -5.0,
    east: 16.0,
    west: -18.0,
    weight: 0.8,
  },
  {
    label: 'East Africa',
    north: 15.0,
    south: -12.5,
    east: 52.0,
    west: 28.0,
    weight: 0.8,
  },
  {
    label: 'Southern Africa',
    north: -10.0,
    south: -35.0,
    east: 40.0,
    west: 11.0,
    weight: 2,
  },
  {
    label: 'Indian Ocean Islands',
    north: -4.0,
    south: -26.0,
    east: 58.0,
    west: 43.0,
    weight: 0.5,
  },
  {
    label: 'Antarctic Peninsula',
    north: -60.0,
    south: -69.0,
    east: -52.0,
    west: -72.0,
    weight: 0.1,
  },
  {
    label: 'Ross Island Antarctica',
    north: -77.0,
    south: -78.5,
    east: 168.0,
    west: 164.0,
    weight: 0.1,
  },
]

const TOTAL_SEARCH_WEIGHT = SEARCH_AREAS.reduce(
  (total, area) => total + area.weight,
  0,
)

const MAX_ATTEMPTS = 90
const POINT_SAMPLE_ATTEMPTS = 40
const HISTORY_DIR = '.streetview-history'
const HISTORY_FILE = 'history.json'
const HISTORY_LIMIT = 1000
const COUNTRY_DATA_FILE = 'data/countries.json'

let historyWriteQueue: Promise<void> = Promise.resolve()
const countryDataCache = new Map<string, Promise<CountryArea[]>>()

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && 'code' in error
}

function getHistoryFilePath(root: string) {
  return join(root, HISTORY_DIR, HISTORY_FILE)
}

function randomInRange(min: number, max: number) {
  return min + Math.random() * (max - min)
}

function pickSearchArea() {
  let threshold = Math.random() * TOTAL_SEARCH_WEIGHT

  for (const area of SEARCH_AREAS) {
    threshold -= area.weight

    if (threshold <= 0) {
      return area
    }
  }

  return SEARCH_AREAS[SEARCH_AREAS.length - 1]
}

function pickPoint(bounds: Bounds) {
  return {
    lat: randomInRange(bounds.south, bounds.north),
    lng: randomInRange(bounds.west, bounds.east),
  }
}

function pickWeighted<T extends { weight: number }>(items: T[]) {
  const totalWeight = items.reduce((total, item) => total + item.weight, 0)
  let threshold = Math.random() * totalWeight

  for (const item of items) {
    threshold -= item.weight

    if (threshold <= 0) {
      return item
    }
  }

  return items[items.length - 1]
}

function isPointInRing(point: { lat: number; lng: number }, ring: Coordinate[]) {
  let isInside = false

  for (
    let index = 0, previousIndex = ring.length - 1;
    index < ring.length;
    previousIndex = index, index += 1
  ) {
    const [currentLng, currentLat] = ring[index]
    const [previousLng, previousLat] = ring[previousIndex]
    const crossesLatitude = currentLat > point.lat !== previousLat > point.lat

    if (!crossesLatitude) {
      continue
    }

    const intersectionLng =
      ((previousLng - currentLng) * (point.lat - currentLat)) /
        (previousLat - currentLat) +
      currentLng

    if (point.lng < intersectionLng) {
      isInside = !isInside
    }
  }

  return isInside
}

function isPointInCountryPart(
  point: { lat: number; lng: number },
  part: CountryPart,
) {
  return (
    isPointInRing(point, part.outer) &&
    part.holes.every((hole) => !isPointInRing(point, hole))
  )
}

function pickPointInCountryPart(part: CountryPart) {
  const [west, south, east, north] = part.bbox

  for (let attempt = 0; attempt < POINT_SAMPLE_ATTEMPTS; attempt += 1) {
    const point = {
      lat: randomInRange(south, north),
      lng: randomInRange(west, east),
    }

    if (isPointInCountryPart(point, part)) {
      return point
    }
  }

  return null
}

function pickPointInCountry(country: CountryArea) {
  for (let attempt = 0; attempt < POINT_SAMPLE_ATTEMPTS; attempt += 1) {
    const part = pickWeighted(country.parts)
    const point = pickPointInCountryPart(part)

    if (point) {
      return point
    }
  }

  throw new Error(`Could not sample a point inside ${country.name}.`)
}

function sendJson(response: ServerResponse, statusCode: number, body: unknown) {
  response.statusCode = statusCode
  response.setHeader('Content-Type', 'application/json')
  response.end(JSON.stringify(body))
}

async function readCountryAreas(root: string) {
  if (!countryDataCache.has(root)) {
    const countryDataPath = join(root, COUNTRY_DATA_FILE)
    countryDataCache.set(
      root,
      readFile(countryDataPath, 'utf8').then((file) => {
        const parsed = JSON.parse(file) as unknown

        if (!Array.isArray(parsed)) {
          throw new Error('Country data must be an array.')
        }

        return parsed as CountryArea[]
      }),
    )
  }

  return countryDataCache.get(root)!
}

function getLocationOptions(countries: CountryArea[]) {
  const continentCounts = new Map<string, number>()

  for (const country of countries) {
    continentCounts.set(
      country.continent,
      (continentCounts.get(country.continent) ?? 0) + 1,
    )
  }

  return {
    continents: Array.from(continentCounts.entries())
      .map(([id, countryCount]) => ({
        id,
        label: id,
        countryCount,
      }))
      .sort((left, right) => left.label.localeCompare(right.label)),
    countries: countries
      .map((country) => ({
        id: country.id,
        code: country.code,
        label: country.name,
        continent: country.continent,
        subregion: country.subregion,
      }))
      .sort((left, right) => left.label.localeCompare(right.label)),
  }
}

async function readHistory(root: string): Promise<HistoryEntry[]> {
  try {
    const file = await readFile(getHistoryFilePath(root), 'utf8')
    const parsed = JSON.parse(file) as unknown
    return Array.isArray(parsed) ? (parsed as HistoryEntry[]) : []
  } catch (error) {
    if (isNodeError(error) && error.code === 'ENOENT') {
      return []
    }

    throw error
  }
}

async function writeHistory(root: string, entries: HistoryEntry[]) {
  const historyDir = join(root, HISTORY_DIR)
  await mkdir(historyDir, { recursive: true })
  await writeFile(getHistoryFilePath(root), `${JSON.stringify(entries, null, 2)}\n`)
}

async function appendHistory(root: string, panorama: RandomPanorama) {
  const entry: HistoryEntry = {
    id: randomUUID(),
    visitedAt: new Date().toISOString(),
    ...panorama,
  }

  const write = historyWriteQueue.then(async () => {
    const currentHistory = await readHistory(root)
    await writeHistory(root, [entry, ...currentHistory].slice(0, HISTORY_LIMIT))
  })

  historyWriteQueue = write.catch(() => undefined)
  await write

  return entry
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

type SearchScopeRequest = {
  continent?: string
  country?: string
}

type SearchScope =
  | {
      kind: 'global'
      label: string
    }
  | {
      kind: 'countries'
      label: string
      countries: CountryArea[]
      selectedCountry?: CountryArea
    }

type SearchCandidate = {
  requestedLocation: {
    lat: number
    lng: number
  }
  areaLabel: string
  scopeLabel: string
  continentLabel?: string
  countryLabel?: string
}

class SearchScopeError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'SearchScopeError'
  }
}

function parseSearchScope(requestUrl: string | undefined): SearchScopeRequest {
  const url = new URL(requestUrl ?? '/', 'http://localhost')

  return {
    continent: url.searchParams.get('continent')?.trim() || undefined,
    country: url.searchParams.get('country')?.trim() || undefined,
  }
}

function resolveCountryScope(
  countries: CountryArea[],
  scope: SearchScopeRequest,
): SearchScope {
  if (scope.country) {
    const selectedCountry = countries.find(
      (country) => country.id === scope.country,
    )

    if (!selectedCountry) {
      throw new SearchScopeError(`Unknown country: ${scope.country}`)
    }

    if (scope.continent && selectedCountry.continent !== scope.continent) {
      throw new SearchScopeError(
        `${selectedCountry.name} is not in ${scope.continent}.`,
      )
    }

    return {
      kind: 'countries',
      label: selectedCountry.name,
      countries: [selectedCountry],
      selectedCountry,
    }
  }

  if (scope.continent) {
    const scopedCountries = countries.filter(
      (country) => country.continent === scope.continent,
    )

    if (scopedCountries.length === 0) {
      throw new SearchScopeError(`Unknown continent: ${scope.continent}`)
    }

    return {
      kind: 'countries',
      label: scope.continent,
      countries: scopedCountries,
    }
  }

  return {
    kind: 'global',
    label: 'World',
  }
}

function pickSearchCandidate(scope: SearchScope): SearchCandidate {
  if (scope.kind === 'global') {
    const area = pickSearchArea()

    return {
      requestedLocation: pickPoint(area),
      areaLabel: area.label,
      scopeLabel: scope.label,
    }
  }

  const country = pickWeighted(scope.countries)
  const areaLabel = scope.selectedCountry
    ? country.name
    : `${scope.label} · ${country.name}`

  return {
    requestedLocation: pickPointInCountry(country),
    areaLabel,
    scopeLabel: scope.label,
    continentLabel: country.continent,
    countryLabel: country.name,
  }
}

async function findRandomPanorama(
  apiKey: string,
  searchScope: SearchScope,
): Promise<RandomPanorama> {
  let lastStatus = 'NO_ATTEMPTS'

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    const candidate = pickSearchCandidate(searchScope)
    const metadata = await getMetadata(apiKey, candidate.requestedLocation)

    lastStatus = metadata.error_message ?? metadata.status

    if (metadata.status === 'OK' && metadata.location && metadata.pano_id) {
      return {
        panoId: metadata.pano_id,
        location: metadata.location,
        requestedLocation: candidate.requestedLocation,
        heading: Math.floor(Math.random() * 360),
        pitch: 0,
        fov: 85,
        date: metadata.date,
        copyright: metadata.copyright,
        areaLabel: candidate.areaLabel,
        scopeLabel: candidate.scopeLabel,
        continentLabel: candidate.continentLabel,
        countryLabel: candidate.countryLabel,
        attempts: attempt,
      }
    }
  }

  throw new Error(
    `No panorama found after ${MAX_ATTEMPTS} tries. Last status: ${lastStatus}`,
  )
}

export function randomStreetViewApi(): Plugin {
  return {
    name: 'random-street-view-api',
    configureServer(server) {
      const env = loadEnv(server.config.mode, server.config.root, '')
      const apiKey = env.GOOGLE_STREET_VIEW_METADATA_API_KEY

      server.middlewares.use('/api/location-options', async (request, response) => {
        if (request.method !== 'GET') {
          sendJson(response, 405, { error: 'Only GET is supported.' })
          return
        }

        try {
          const countries = await readCountryAreas(server.config.root)
          sendJson(response, 200, getLocationOptions(countries))
        } catch (error) {
          sendJson(response, 500, {
            error: 'Could not read location options.',
            details: error instanceof Error ? error.message : String(error),
          })
        }
      })

      server.middlewares.use('/api/history', async (request, response) => {
        if (request.method !== 'GET') {
          sendJson(response, 405, { error: 'Only GET is supported.' })
          return
        }

        try {
          sendJson(response, 200, await readHistory(server.config.root))
        } catch (error) {
          sendJson(response, 500, {
            error: 'Could not read local visit history.',
            details: error instanceof Error ? error.message : String(error),
          })
        }
      })

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
          const countries = await readCountryAreas(server.config.root)
          const searchScope = resolveCountryScope(
            countries,
            parseSearchScope(request.url),
          )
          const panorama = await findRandomPanorama(apiKey, searchScope)
          await appendHistory(server.config.root, panorama)
          sendJson(response, 200, panorama)
        } catch (error) {
          if (error instanceof SearchScopeError) {
            sendJson(response, 400, {
              error: 'Invalid location filter.',
              details: error.message,
            })
            return
          }

          sendJson(response, 502, {
            error: 'Could not find a usable Street View panorama.',
            details: error instanceof Error ? error.message : String(error),
          })
        }
      })
    },
  }
}
