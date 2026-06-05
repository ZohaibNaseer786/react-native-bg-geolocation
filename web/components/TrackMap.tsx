'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { cleanTrack, type TrackPoint } from '@/lib/locations';

const DEFAULT_CENTER = { lat: 30.8255, lng: 73.4646 };
const MAPS_KEY = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY ?? '';

// ─── Plain Google Maps script loader (no third-party React wrapper) ────────────
let mapsPromise: Promise<void> | null = null;
function loadGoogleMaps(key: string): Promise<void> {
  if (typeof window === 'undefined')
    return Promise.reject(new Error('no window'));
  if ((window as any).google?.maps) return Promise.resolve();
  if (mapsPromise) return mapsPromise;

  mapsPromise = new Promise<void>((resolve, reject) => {
    (window as any).__initGMaps = () => resolve();
    (window as any).gm_authFailure = () =>
      reject(
        new Error('Auth failed — check key, billing, or allowed referrers')
      );

    const s = document.createElement('script');
    s.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(key)}&callback=__initGMaps`;
    s.async = true;
    s.defer = true;
    s.onerror = () => reject(new Error('Failed to load Google Maps script'));
    document.head.appendChild(s);
  });
  return mapsPromise;
}

// ─── Parent: panel + data fetch. No map dependency. Always renders. ────────────
export default function TrackMap() {
  const [mounted, setMounted] = useState(false);
  const [points, setPoints] = useState<TrackPoint[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [autoRefresh, setAuto] = useState(true);
  const [lastFetch, setLastFetch] = useState('—');
  const [clean, setClean] = useState(true);

  useEffect(() => {
    setMounted(true);
  }, []);

  // Cleaned (spikes + stationary duplicates removed) vs raw points
  const shownPoints = useMemo(
    () => (clean ? cleanTrack(points) : points),
    [points, clean]
  );

  const fetchPoints = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch('/api/locations', { cache: 'no-store' });
      const json = await res.json();
      if (!res.ok) throw new Error(json?.error ?? `HTTP ${res.status}`);
      setPoints(json.points ?? []);
      setLastFetch(new Date().toLocaleTimeString());
      if ((json.points ?? []).length === 0 && json.debug?.rawSample) {
        setError(
          '0 points parsed. Raw: ' +
            JSON.stringify(json.debug.rawSample).slice(0, 200)
        );
      }
    } catch (e: any) {
      setError(e?.message ?? 'fetch failed');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!mounted) return;
    fetchPoints();
    if (!autoRefresh) return;
    const id = setInterval(fetchPoints, 15_000);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mounted, autoRefresh]);

  const start = shownPoints[0];
  const end = shownPoints[shownPoints.length - 1];
  const removed = points.length - shownPoints.length;

  return (
    <div
      style={{
        position: 'relative',
        width: '100vw',
        height: '100vh',
        background: '#0d1117',
      }}
    >
      <div style={styles.panel}>
        <div style={styles.title}>📍 Tracking Viewer</div>
        <div style={styles.row}>
          <span style={styles.label}>Showing</span>
          <b style={styles.val}>{shownPoints.length}</b>
        </div>
        <div style={styles.row}>
          <span style={styles.label}>Raw total</span>
          <span style={styles.val}>{points.length}</span>
        </div>
        {clean && removed > 0 && (
          <div style={styles.row}>
            <span style={styles.label}>Filtered</span>
            <span style={styles.valSmall}>{removed} spikes/dupes</span>
          </div>
        )}
        <div style={styles.row}>
          <span style={styles.label}>Last fetch</span>
          <span style={styles.val}>{lastFetch}</span>
        </div>
        {start?.timestamp && (
          <div style={styles.row}>
            <span style={styles.label}>First</span>
            <span style={styles.valSmall}>
              {new Date(start.timestamp).toLocaleString()}
            </span>
          </div>
        )}
        {end?.timestamp && (
          <div style={styles.row}>
            <span style={styles.label}>Last</span>
            <span style={styles.valSmall}>
              {new Date(end.timestamp).toLocaleString()}
            </span>
          </div>
        )}
        {error && <div style={styles.error}>⚠ {error}</div>}
        <div style={styles.buttons}>
          <button style={styles.btn} onClick={fetchPoints} disabled={loading}>
            {loading ? 'Loading…' : '↻ Refresh'}
          </button>
          <button
            style={{
              ...styles.btn,
              background: autoRefresh ? '#238636' : '#21262d',
            }}
            onClick={() => setAuto((v) => !v)}
          >
            {autoRefresh ? '⏸ Auto 15s' : '▶ Auto off'}
          </button>
        </div>
        <div style={styles.buttons}>
          <button
            style={{ ...styles.btn, background: clean ? '#238636' : '#21262d' }}
            onClick={() => setClean((v) => !v)}
          >
            {clean ? '✓ Clean path' : '○ Raw path'}
          </button>
        </div>
      </div>

      {!mounted ? (
        <Centered>Initializing…</Centered>
      ) : !MAPS_KEY ? (
        <Centered>
          Set <code>NEXT_PUBLIC_GOOGLE_MAPS_API_KEY</code> in{' '}
          <code>web/.env.local</code> and restart.
        </Centered>
      ) : (
        <MapCanvas points={shownPoints} />
      )}
    </div>
  );
}

// ─── Child: vanilla google.maps via injected script ────────────────────────────
function MapCanvas({ points }: { points: TrackPoint[] }) {
  const divRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<any>(null);
  const markersRef = useRef<any[]>([]);
  const polylineRef = useRef<any>(null);
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>(
    'loading'
  );
  const [errMsg, setErrMsg] = useState('');

  // Load script + create the map once.
  useEffect(() => {
    let cancelled = false;
    loadGoogleMaps(MAPS_KEY)
      .then(() => {
        if (cancelled || !divRef.current) return;
        const g = (window as any).google;
        mapRef.current = new g.maps.Map(divRef.current, {
          center: DEFAULT_CENTER,
          zoom: 15,
          minZoom: 3,
          maxZoom: 18, // fitBounds respects this — prevents over-zoom into grey
          mapTypeControl: true,
          streetViewControl: false,
          fullscreenControl: true,
        });
        setStatus('ready');
      })
      .catch((e) => {
        if (!cancelled) {
          setErrMsg(e.message);
          setStatus('error');
        }
      });
    return () => {
      cancelled = true;
    };
  }, []);

  // Draw / redraw points whenever they change.
  useEffect(() => {
    if (status !== 'ready' || !mapRef.current) return;
    const g = (window as any).google;

    markersRef.current.forEach((m) => m.setMap(null));
    markersRef.current = [];
    polylineRef.current?.setMap(null);

    if (points.length === 0) return;

    const path = points.map((p) => ({ lat: p.lat, lng: p.lng }));
    polylineRef.current = new g.maps.Polyline({
      path,
      map: mapRef.current,
      strokeColor: '#1f6feb',
      strokeWeight: 4,
      strokeOpacity: 0.85,
    });

    points.forEach((p, i) => {
      const isStart = i === 0;
      const isEnd = i === points.length - 1;
      markersRef.current.push(
        new g.maps.Marker({
          position: { lat: p.lat, lng: p.lng },
          map: mapRef.current,
          title: `#${i + 1}${p.timestamp ? ' · ' + new Date(p.timestamp).toLocaleString() : ''}\n${p.lat}, ${p.lng}`,
          icon: {
            path: g.maps.SymbolPath.CIRCLE,
            scale: isStart || isEnd ? 8 : 4,
            fillColor: isStart ? '#238636' : isEnd ? '#da3633' : '#1f6feb',
            fillOpacity: 1,
            strokeColor: '#fff',
            strokeWeight: isStart || isEnd ? 2 : 1,
          },
        })
      );
    });

    if (points.length === 1) {
      mapRef.current.setCenter(path[0]);
      mapRef.current.setZoom(17);
    } else {
      const bounds = new g.maps.LatLngBounds();
      path.forEach((pt: any) => bounds.extend(pt));
      mapRef.current.fitBounds(bounds, 64); // respects map maxZoom (18)
    }
  }, [points, status]);

  return (
    <>
      <div ref={divRef} style={{ width: '100%', height: '100%' }} />
      {status === 'loading' && <Overlay>Loading map…</Overlay>}
      {status === 'error' && <Overlay>Map error: {errMsg}</Overlay>}
    </>
  );
}

function Centered({ children }: { children: React.ReactNode }) {
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        width: '100%',
        height: '100%',
        color: '#e6edf3',
        textAlign: 'center',
        padding: 24,
      }}
    >
      <div>{children}</div>
    </div>
  );
}
function Overlay({ children }: { children: React.ReactNode }) {
  return (
    <div
      style={{
        position: 'absolute',
        inset: 0,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        color: '#e6edf3',
        background: 'rgba(13,17,23,0.4)',
        pointerEvents: 'none',
      }}
    >
      <div>{children}</div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  panel: {
    position: 'absolute',
    top: 16,
    left: 16,
    zIndex: 10,
    background: 'rgba(13,17,23,0.92)',
    color: '#e6edf3',
    borderRadius: 10,
    padding: 14,
    width: 240,
    border: '1px solid #30363d',
    backdropFilter: 'blur(8px)',
    fontSize: 13,
  },
  title: { fontWeight: 700, fontSize: 15, marginBottom: 10 },
  row: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: '3px 0',
  },
  label: { color: '#8b949e' },
  val: { color: '#e6edf3', fontWeight: 600 },
  valSmall: { color: '#e6edf3', fontSize: 11 },
  error: {
    color: '#f85149',
    fontSize: 12,
    marginTop: 8,
    wordBreak: 'break-word',
  },
  buttons: { display: 'flex', gap: 8, marginTop: 12 },
  btn: {
    flex: 1,
    background: '#1f6feb',
    color: '#fff',
    border: 'none',
    borderRadius: 6,
    padding: '8px 6px',
    fontSize: 12,
    fontWeight: 600,
    cursor: 'pointer',
  },
};
