# BG Geolocation — Tracking Viewer (Next.js)

A small web app to visualise the location points your device sent to the server.
Draws every point on a Google Map and connects them with a travel-path polyline.

## Setup

```sh
cd web
npm install            # or: yarn
cp .env.local.example .env.local
```

Edit `.env.local`:

| Var | What |
|---|---|
| `NEXT_PUBLIC_GOOGLE_MAPS_API_KEY` | Google Maps **JavaScript API** key (enable the API + billing in Google Cloud). |
| `LOCATIONS_API_URL` | Your server endpoint that returns saved locations (e.g. `https://…/locations`). |
| `LOCATIONS_AUTH_TOKEN` | Bearer token for that endpoint. Stays server-side (never sent to the browser). |

## Run

```sh
npm run dev
# open http://localhost:3001
```

## How it works

- `app/api/locations/route.ts` — server-side proxy that calls `LOCATIONS_API_URL`
  with the Bearer token (avoids CORS, keeps the token secret), then normalises the
  response via `lib/locations.ts`.
- `lib/locations.ts` — flexible parser. Handles `{lat,long}`, `{latitude,longitude}`,
  `{coords:{…}}`, arrays under `data`/`locations`/`results`/`items`, and sorts by
  timestamp so the path draws in travel order.
- `components/TrackMap.tsx` — Google Map with markers (🟢 start, 🔴 end, 🔵 path)
  + polyline, auto-fit bounds, and 15s auto-refresh.

If your API returns a different shape, paste a sample response and the parser can be
adjusted in `lib/locations.ts`.
