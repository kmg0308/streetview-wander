# StreetView Wander

StreetView Wander is a localhost-only random Google Street View explorer.

It picks a random coordinate from broad Street View coverage areas, checks that
Google has outdoor Street View imagery for the coordinate, then opens the
nearest valid panorama beside a Google Map.

## Features

- Random Street View start point
- Free movement inside the Google Street View iframe
- Google Map shown next to the current start point
- Server-side metadata lookup so the metadata key is not exposed to browser code
- No Maps JavaScript API or Dynamic Street View usage

## Google Cloud setup

Create two API keys in Google Cloud:

1. Browser key
   - Enable API: Maps Embed API
   - Application restriction: Websites
   - Allowed referrers:
     - `http://localhost:*/*`
     - `http://127.0.0.1:*/*`
   - API restriction: Maps Embed API

2. Metadata key
   - Enable API: Street View Static API
   - API restriction: Street View Static API
   - Store it only in `.env`

The app uses the metadata endpoint only. Google documents Street View metadata
requests as no-charge requests that do not consume quota. The visible Street
View and map are loaded through Maps Embed API.

## Local setup

```bash
npm install
cp .env.example .env
npm run dev
```

Then fill `.env`:

```bash
VITE_GOOGLE_MAPS_EMBED_API_KEY=your_browser_key
GOOGLE_STREET_VIEW_METADATA_API_KEY=your_metadata_key
```

Restart the dev server after changing `.env`.

## Commands

```bash
npm run dev
npm run build
npm run lint
```
