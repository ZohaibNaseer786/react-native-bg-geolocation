import { NextResponse } from 'next/server';
import { extractPoints } from '@/lib/locations';

export const dynamic = 'force-dynamic'; // never cache — we want live data

/**
 * Server-side proxy to the tracking server's locations endpoint.
 * Keeps the auth token on the server and avoids browser CORS issues.
 */
export async function GET() {
  const url = process.env.LOCATIONS_API_URL;
  const token = process.env.LOCATIONS_AUTH_TOKEN;

  if (!url) {
    return NextResponse.json(
      {
        error:
          'LOCATIONS_API_URL is not set. Copy .env.local.example → .env.local.',
      },
      { status: 500 }
    );
  }

  try {
    const res = await fetch(url, {
      headers: {
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        Accept: 'application/json',
      },
      cache: 'no-store',
    });

    const text = await res.text();
    let body: any;
    try {
      body = JSON.parse(text);
    } catch {
      body = text;
    }

    if (!res.ok) {
      return NextResponse.json(
        { error: `Upstream ${res.status}`, detail: body },
        { status: res.status }
      );
    }

    const points = extractPoints(body);
    // If nothing parsed, echo a sample of the raw upstream body to help debug the shape.
    const debug =
      points.length === 0
        ? { rawSample: typeof body === 'string' ? body.slice(0, 500) : body }
        : undefined;
    return NextResponse.json({
      count: points.length,
      points,
      ...(debug ? { debug } : {}),
    });
  } catch (e: any) {
    return NextResponse.json(
      { error: e?.message ?? 'fetch failed' },
      { status: 502 }
    );
  }
}
