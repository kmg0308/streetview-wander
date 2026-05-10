# StreetView Wander

StreetView Wander is a localhost-only random Google Street View explorer.

It picks a random coordinate from broad Street View coverage areas, checks that
Google has outdoor Street View imagery for the coordinate, then opens the
nearest valid panorama with a floating Google Map.

## Features

- Random Street View start point
- Searchable continent and country filters for the next random place
- Free movement inside full-screen Google Street View, loaded by panorama ID
- Floating Google Map for the current start point, with wheel zoom enabled
- Minimal controls so Street View stays as the main full-screen view
- Local visit history, viewable in the browser
- Server-side metadata lookup so the metadata key is not exposed to browser code

The random picker uses broad weighted regions across North America, Europe,
Asia, Oceania, South America, Africa, and island regions. Google does not expose
a downloadable list of every Street View panorama, so the app still verifies each
random coordinate with the Street View metadata endpoint before opening it.
When a continent or country filter is selected, the app samples from local
Natural Earth country boundary data before running the Street View metadata
check.

## Google Cloud setup

Create two API keys in Google Cloud:

1. Browser key
   - Enable API: Maps JavaScript API
   - Application restriction: Websites
   - Allowed referrers:
     - `http://localhost:5173/*`
     - `http://127.0.0.1:5173/*`
   - API restriction: Maps JavaScript API

2. Metadata key
   - Enable API: Street View Static API
   - API restriction: Street View Static API
   - Store it only in `.env`

The server uses the metadata endpoint to find a valid panorama. Google
documents Street View metadata requests as no-charge requests that do not
consume quota. The visible Street View and floating map are loaded through Maps
JavaScript API so wheel zoom works on the map and Google's default view controls
can be hidden.

## Local setup

```bash
npm install
cp .env.example .env
npm run dev
```

Then fill `.env`:

```bash
VITE_GOOGLE_MAPS_API_KEY=your_browser_key
GOOGLE_STREET_VIEW_METADATA_API_KEY=your_metadata_key
```

Restart the dev server after changing `.env`.

Random visits are saved locally to `.streetview-history/history.json`. That
folder is ignored by git.

## Commands

```bash
npm run dev
npm run build
npm run lint
```
