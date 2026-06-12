import { io, type Socket } from 'socket.io-client';
import {
  EXAMPLE_AUTH_TOKEN,
  EXAMPLE_LOCATION_FALLBACK_PATH,
  EXAMPLE_SERVER_BASE_URL,
  EXAMPLE_SOCKET_EVENT,
  EXAMPLE_SOCKET_PATH,
} from './exampleConfig';

// ─── Config ───────────────────────────────────────────────────────────────────
export const SERVER_BASE_URL = EXAMPLE_SERVER_BASE_URL;
export const SOCKET_PATH = EXAMPLE_SOCKET_PATH;
export const SOCKET_LOCATION_EVENT = EXAMPLE_SOCKET_EVENT;
const CONNECT_TIMEOUT_MS = 6_000;
const ACK_TIMEOUT_MS = 10_000;

export const AUTH_TOKEN = EXAMPLE_AUTH_TOKEN;

export interface Coordinates {
  latitude: number;
  longitude: number;
}

// REST fallback used when the socket can't deliver.
const FALLBACK_PATH = EXAMPLE_LOCATION_FALLBACK_PATH;

const fmt = (l: Coordinates) =>
  `${l.latitude.toFixed(6)}, ${l.longitude.toFixed(6)}`;

// Local wall-clock time as "HH:mm" (matches the fallback payload's userCurrentTime).
function currentTimeHHmm(): string {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// The device push token the fallback endpoint keys off. Set via setFcmToken();
// on iOS without a Firebase integration, pass the APNs device token instead.
let fcmToken: string | null = null;
export function setFcmToken(token: string | null): void {
  fcmToken = token;
}
export function getFcmToken(): string | null {
  return fcmToken;
}

let socket: Socket | null = null;
let queuedLocation: Coordinates | null = null;

// ─── REST fallback ──────────────────────────────────────────────────────────
/**
 * REST fallback used when the socket can't deliver. POSTs to
 * /api/location/fallback with the payload the backend expects.
 *
 * Used when:
 *   1. Socket can't connect (background/foreground fallback).
 *   2. Socket ack times out.
 *   3. Kill state / headless task — socket.io is unreliable in short-lived JS
 *      contexts because it needs TCP → TLS → WS upgrade → auth before emitting.
 */
export async function sendLocationViaHttp(loc: Coordinates): Promise<boolean> {
  try {
    console.log('[BgGeoTest][LocationSocket] 🌐 REST fallback →', fmt(loc));
    const res = await fetch(`${SERVER_BASE_URL}${FALLBACK_PATH}`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${AUTH_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        latitude: loc.latitude,
        longitude: loc.longitude,
        fcmToken: fcmToken ?? '',
        userCurrentTime: currentTimeHHmm(),
      }),
    });
    console.log('[BgGeoTest][LocationSocket] 🌐 REST status:', res.status);
    return res.ok;
  } catch (e: any) {
    console.log('[BgGeoTest][LocationSocket] 🌐 REST error:', e?.message ?? e);
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
