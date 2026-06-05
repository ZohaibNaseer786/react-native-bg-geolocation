import { io, type Socket } from 'socket.io-client';

// ─── Config ───────────────────────────────────────────────────────────────────
export const SERVER_BASE_URL = 'https://masjidpilot.duckdns.org';
const SOCKET_PATH = '/socket/location';
const CONNECT_TIMEOUT_MS = 6_000;
const ACK_TIMEOUT_MS = 10_000;

export const AUTH_TOKEN =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiI2OWViNDk0NzYxMDRlOWEwZTc2M2JhNTEiLCJyb2xlIjoic3VwZXJfYWRtaW4iLCJpYXQiOjE3ODAxMjAwNDUsImV4cCI6MTc4MjcxMjA0NX0.qJLZgp32ETKAE4G1pf6NiX3JJFVX6AkTSG0zp5tA5Sk';

export interface Coordinates {
  latitude: number;
  longitude: number;
}

const fmt = (l: Coordinates) =>
  `${l.latitude.toFixed(6)}, ${l.longitude.toFixed(6)}`;

let socket: Socket | null = null;
let queuedLocation: Coordinates | null = null;

// ─── HTTP fallback ────────────────────────────────────────────────────────────
/**
 * Plain fetch()-based REST POST.
 *
 * Used in two situations:
 *   1. Socket can't connect (background/foreground fallback).
 *   2. Kill state / headless task — socket.io is unreliable in short-lived JS
 *      contexts because it needs TCP → TLS → WS upgrade → auth before emitting.
 *      A simple fetch() POST works immediately.
 */
export async function sendLocationViaHttp(loc: Coordinates): Promise<boolean> {
  try {
    console.log('[BgGeoTest][LocationSocket] 🌐 HTTP fallback →', fmt(loc));
    const res = await fetch(`${SERVER_BASE_URL}/location`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${AUTH_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        lat: loc.latitude,
        long: loc.longitude,
        latitude: loc.latitude,
        longitude: loc.longitude,
      }),
    });
    console.log('[BgGeoTest][LocationSocket] 🌐 HTTP status:', res.status);
    return res.ok;
  } catch (e: any) {
    console.log('[BgGeoTest][LocationSocket] 🌐 HTTP error:', e?.message ?? e);
    return false;
  }
}

// ─── Socket ───────────────────────────────────────────────────────────────────
function createSocket(): Socket {
  console.log('[BgGeoTest][LocationSocket] Connecting', {
    url: SERVER_BASE_URL,
    path: SOCKET_PATH,
  });

  const s = io(SERVER_BASE_URL, {
    path: SOCKET_PATH,
    transports: ['websocket'],
    auth: { token: AUTH_TOKEN },
    reconnection: true,
    reconnectionAttempts: Infinity,
    reconnectionDelay: 1_000,
    reconnectionDelayMax: 10_000,
    timeout: 10_000,
    autoConnect: true,
  });

  s.on('connect', () => {
    console.log('[BgGeoTest][LocationSocket] ✅ Connected', { id: s.id });
    if (queuedLocation) {
      const loc = queuedLocation;
      queuedLocation = null;
      sendLocationToSocket(loc).catch(() => {
        queuedLocation = loc;
      });
    }
  });

  s.on('disconnect', (reason) =>
    console.log('[BgGeoTest][LocationSocket] ❌ Disconnected', reason)
  );
  s.on('connect_error', (err) =>
    console.log('[BgGeoTest][LocationSocket] connect_error', err.message)
  );
  s.on('location-saved', (resp) =>
    console.log('[BgGeoTest][LocationSocket] location-saved', resp)
  );
  s.on('location-error', (err) =>
    console.log('[BgGeoTest][LocationSocket] location-error', err)
  );

  return s;
}

export function connectLocationSocket(): Socket {
  if (socket) {
    if (!socket.connected) socket.connect();
    return socket;
  }
  socket = createSocket();
  return socket;
}

function waitForConnection(s: Socket): Promise<boolean> {
  if (s.connected) return Promise.resolve(true);
  return new Promise((resolve) => {
    let settled = false;
    const finish = (ok: boolean) => {
      if (settled) return;
      settled = true;
      s.off('connect', onConnect);
      s.off('connect_error', onError);
      clearTimeout(timer);
      resolve(ok);
    };
    const onConnect = () => finish(true);
    const onError = () => finish(false);
    const timer = setTimeout(() => finish(false), CONNECT_TIMEOUT_MS);
    s.once('connect', onConnect);
    s.once('connect_error', onError);
    s.connect();
  });
}

function emitLocationUpdate(s: Socket, loc: Coordinates): Promise<boolean> {
  return new Promise((resolve) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      console.log('[BgGeoTest][LocationSocket] ack timed out');
      resolve(false);
    }, ACK_TIMEOUT_MS);

    s.emit(
      'location:update',
      { latitude: loc.latitude, longitude: loc.longitude },
      (response?: { ok?: boolean; error?: string }) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        if (response?.ok === false) {
          console.log(
            '[BgGeoTest][LocationSocket] server rejected:',
            response.error
          );
          resolve(false);
          return;
        }
        console.log(
          '[BgGeoTest][LocationSocket] ✅ server acknowledged location:update'
        );
        resolve(true);
      }
    );
  });
}

/**
 * Send a location to the server.
 *
 * Strategy:
 *   1. Try socket.io (fastest when already connected).
 *   2. If socket can't connect within 6s → HTTP REST fallback.
 *   3. If socket ack times out → HTTP REST fallback.
 *
 * For kill-state / headless tasks, the socket will almost never be connected,
 * so this immediately falls through to the HTTP fallback — which is fine.
 */
export async function sendLocationToSocket(loc: Coordinates): Promise<boolean> {
  const s = connectLocationSocket();
  const connected = await waitForConnection(s);

  if (!connected) {
    console.log(
      '[BgGeoTest][LocationSocket] socket unavailable → HTTP fallback',
      fmt(loc)
    );
    const ok = await sendLocationViaHttp(loc);
    if (!ok) queuedLocation = loc; // retry next time socket connects
    return ok;
  }

  console.log(
    '[BgGeoTest][LocationSocket] → sending location:update',
    fmt(loc)
  );
  const ok = await emitLocationUpdate(s, loc);
  if (!ok) {
    console.log('[BgGeoTest][LocationSocket] emit failed → HTTP fallback');
    return sendLocationViaHttp(loc);
  }
  return true;
}

export function disconnectLocationSocket(): void {
  if (socket) {
    console.log('[BgGeoTest][LocationSocket] Disconnecting');
    socket.removeAllListeners();
    socket.disconnect();
  }
  socket = null;
  queuedLocation = null;
}
