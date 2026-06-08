/**
 * App-level background location orchestrator.
 *
 * Mirrors the production MasjidPilot `backgroundLocationService.ts` structure:
 *   - registerListeners()          — onLocation / onHeartbeat / onProviderChange
 *   - ensureReady()                — BackgroundGeolocation.ready() once
 *   - startBackgroundTracking()    — request permission → connect socket → start
 *   - stopBackgroundTracking()     — stop + disconnect
 *   - Android headless task registered at MODULE SCOPE (bottom of file)
 *
 * Android headless delivery uses the socket/HTTP fallback. iOS uses native
 * HTTP during an OS-managed location relaunch because React Native may not
 * finish booting inside the short background wake.
 */
import { Platform } from 'react-native';
import BackgroundGeolocation, {
  type Config,
  type HeadlessEvent,
  type HeartbeatEvent,
  type Location,
  type LocationError,
  type State,
  type Subscription,
} from 'react-native-bg-geolocation';
import {
  AUTH_TOKEN,
  SERVER_BASE_URL,
  connectLocationSocket,
  disconnectLocationSocket,
  sendLocationToSocket,
  type Coordinates,
} from './locationSocketService';

const LOCATION_SOCKET_INTERVAL_MS = 60 * 1000;
const LOCATION_SOCKET_HEARTBEAT_SECONDS = 60;
const IOS_MOTION_STATUS_AUTHORIZED = 3;

let readyPromise: Promise<State> | null = null;
let subscriptions: Subscription[] = [];
let foregroundInterval: ReturnType<typeof setInterval> | null = null;
let lastSocketLocationSentAt = 0;

// Optional UI hooks (so the example screen can render live state)
export interface BgLocationHooks {
  onEvent?: (msg: string) => void;
  onLocation?: (location: Location) => void;
  onMotionChange?: (isMoving: boolean, activity?: string) => void;
  onEnabledChange?: (enabled: boolean) => void;
  onSocketStatus?: (
    status: 'connecting' | 'connected' | 'disconnected'
  ) => void;
}
let hooks: BgLocationHooks = {};
export function setBgLocationHooks(h: BgLocationHooks) {
  hooks = h;
}

const log = (msg: string) => {
  console.log('[BgGeoTest][BackgroundLocation]', msg);
  hooks.onEvent?.(msg);
};

// ─── Helpers ────────────────────────────────────────────────────────────────
function toCoordinates(location: Location): Coordinates {
  return {
    latitude: location.coords.latitude,
    longitude: location.coords.longitude,
  };
}

/**
 * Send a location to the socket, throttled to once per minute (unless forced).
 */
async function sendLocationUpdate(
  location: Location,
  options: { force?: boolean } = {}
): Promise<void> {
  const now = Date.now();
  if (
    !options.force &&
    lastSocketLocationSentAt > 0 &&
    now - lastSocketLocationSentAt < LOCATION_SOCKET_INTERVAL_MS
  ) {
    return;
  }
  log(
    `→ sending location ${location.coords.latitude.toFixed(5)}, ${location.coords.longitude.toFixed(5)} (force=${!!options.force})`
  );
  const sent = await sendLocationToSocket(toCoordinates(location));
  if (sent) {
    lastSocketLocationSentAt = now;
    log('✅ socket send OK');
  } else {
    log('❌ socket send failed');
  }
}

/**
 * On heartbeat, use the heartbeat's location if present, otherwise fetch a fix.
 */
async function sendHeartbeatLocation(event?: HeartbeatEvent): Promise<void> {
  try {
    log('💓 heartbeat');
    const location =
      event?.location?.coords != null
        ? event.location
        : await BackgroundGeolocation.getCurrentPosition({
            samples: 1,
            persist: true,
            maximumAge: LOCATION_SOCKET_INTERVAL_MS,
            timeout: 30,
          });
    await sendLocationUpdate(location, { force: true });
  } catch {
    log('heartbeat: location unavailable');
  }
}

function startForegroundInterval(): void {
  if (foregroundInterval) return;
  foregroundInterval = setInterval(() => {
    log('⏱ foreground interval');
    sendHeartbeatLocation().catch(() => {});
  }, LOCATION_SOCKET_INTERVAL_MS);
}

function stopForegroundInterval(): void {
  if (foregroundInterval) {
    clearInterval(foregroundInterval);
    foregroundInterval = null;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ─── Config ─────────────────────────────────────────────────────────────────
function getConfig(): Config {
  return {
    reset: false,
    geolocation: {
      desiredAccuracy: BackgroundGeolocation.DesiredAccuracy.High,
      distanceFilter: 10,
      locationAuthorizationRequest: 'Always',
      pausesLocationUpdatesAutomatically: false,
      showsBackgroundLocationIndicator: true,
      stopTimeout: 5,
      // "Ride app" mode: keep GPS running continuously for the whole session so
      // the app stays alive in the background (status-bar location indicator
      // shown) instead of powering down to the battery-saving stationary state.
      // Higher battery use, far more reliable background tracking.
      disableStopDetection: true,
    },
    app: {
      stopOnTerminate: false,
      startOnBoot: true,
      enableHeadless: true,
      heartbeatInterval: LOCATION_SOCKET_HEARTBEAT_SECONDS,
      preventSuspend: true,
      ...(Platform.OS === 'ios'
        ? {
            liveActivityEnabled: true,
            liveActivityTitle: 'Live location',
            liveActivitySubtitle: 'Background tracking is active',
            liveActivityUpdateInterval: 15,
            // If iOS stops delivering updates (including a user force-quit),
            // ActivityKit marks the notification stale and the widget tells
            // the user to reopen the app instead of claiming tracking is live.
            liveActivityStaleSeconds: 90,
            // Local ActivityKit updates need no APNs entitlement. Enable push
            // updates only after adding the Push Notifications capability and
            // implementing the server-side ActivityKit APNs flow.
            liveActivityPushUpdates: false,
            // Apple-approved private-distribution tracking session: play a real,
            // audible low-volume tone while tracking is active. Start/Stop in
            // the app is the user control; the Live Activity remains the
            // tracking UI and no Now Playing metadata is published.
            trackingAudioEnabled: true,
            trackingAudioVolume: 0.04,
            trackingAudioMixWithOthers: true,
            // Kill-state tracking: server sends an APNs background push to the
            // device's location-push token → iOS wakes the Location Push Service
            // Extension → it captures one location and POSTs it to `url`. Needs
            // the Apple-approved com.apple.developer.location.push entitlement.
            locationPushEnabled: true,
          }
        : {}),
      foregroundService: true,
      notification: {
        sticky: true,
        title: 'Location is active',
        text: 'Tracking your location in the background.',
        channelName: 'Background location',
      },
      backgroundPermissionRationale: {
        title: 'Allow location in the background',
        message:
          'This app needs Always location access to keep tracking when the app is closed.',
        positiveAction: 'Open Settings',
        negativeAction: 'Not now',
      },
    },
    logger: {
      debug: true,
      logLevel: BackgroundGeolocation.LogLevel.Verbose,
    },

    // ── iOS kill-state delivery ───────────────────────────────────────────────
    // On iOS the OS only wakes a system-terminated app briefly (significant-change /
    // stationary-region exit). Booting RN + the socket in that window is
    // unreliable, so we let the NATIVE layer POST the fix directly to the REST
    // endpoint the instant it's woken. Android keeps using the JS socket via the
    // headless task (its foreground service makes that reliable).
    ...(Platform.OS === 'ios'
      ? {
          http: {
            url: `${SERVER_BASE_URL}/location`,
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${AUTH_TOKEN}`,
              'Content-Type': 'application/json',
            },
            // Match the foreground HTTP fallback: send the location record at
            // the root with flat lat/long aliases added by the native engine.
            rootProperty: '',
            autoSync: true,
          },
        }
      : {}),
  };
}

// ─── Listeners ──────────────────────────────────────────────────────────────
function registerListeners(): void {
  if (subscriptions.length > 0) return;

  subscriptions = [
    BackgroundGeolocation.onLocation(
      (location: Location) => {
        log(
          `📍 onLocation ${location.coords.latitude.toFixed(5)}, ${location.coords.longitude.toFixed(5)} moving=${location.is_moving} activity=${location.activity?.type}`
        );
        hooks.onLocation?.(location);
        sendLocationUpdate(location, { force: true }).catch(() => {});
      },
      (error: LocationError) => log(`location error: ${JSON.stringify(error)}`)
    ),
    BackgroundGeolocation.onHeartbeat((event: HeartbeatEvent) => {
      sendHeartbeatLocation(event).catch(() => {});
    }),
    BackgroundGeolocation.onMotionChange((event: any) => {
      log(
        `🔄 motionchange isMoving=${event.isMoving} activity=${event.activity?.type}`
      );
      hooks.onMotionChange?.(!!event.isMoving, event.activity?.type);
    }),
    BackgroundGeolocation.onEnabledChange((enabled: boolean) => {
      log(`enabledchange=${enabled}`);
      hooks.onEnabledChange?.(enabled);
    }),
    BackgroundGeolocation.onProviderChange((event: any) => {
      log(`providerchange enabled=${event.enabled} gps=${event.gps}`);
    }),
  ];
}

async function ensureReady(): Promise<State> {
  if (!readyPromise) {
    registerListeners();
    readyPromise = BackgroundGeolocation.ready(getConfig());
    readyPromise.then(() => {
      // Fire-and-forget: ship the iOS location-push token to the server so it
      // can trigger kill-state location fetches via the Location Push Service
      // Extension. No-op on Android (resolves null).
      void registerLocationPushToken();
    });
  }
  return readyPromise;
}

/**
 * iOS only. Fetches the device's location-push APNs token and registers it with
 * the server. The token may not be ready on the very first launch (iOS returns
 * it asynchronously after `startMonitoringLocationPushes`); we retry briefly.
 *
 * Once the server has the token it can POST to Apple's APNs
 * (apns-topic: <bundle-id>.location-push, apns-push-type: background) to wake
 * the extension and have it upload a fresh location — even when the app is
 * force-quit.
 */
export async function registerLocationPushToken(): Promise<string | null> {
  if (Platform.OS !== 'ios') return null;

  let token: string | null = null;
  for (let attempt = 0; attempt < 5; attempt++) {
    token = await BackgroundGeolocation.getLocationPushToken().catch(() => null);
    if (token) break;
    await sleep(1500);
  }

  if (!token) {
    log('⚠️ location-push token not available yet (entitlement pending?)');
    return null;
  }

  log(`🔑 location-push token: ${token.slice(0, 12)}…`);
  try {
    const res = await fetch(`${SERVER_BASE_URL}/location-push/register`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${AUTH_TOKEN}`,
      },
      body: JSON.stringify({
        token,
        platform: 'ios',
        // apns-topic the server must use when pushing to this token.
        topic: 'com.masjidpilot.staging.location-push',
      }),
    });
    log(`location-push token register → HTTP ${res.status}`);
  } catch (err) {
    log(`❌ failed to register location-push token: ${String(err)}`);
  }
  return token;
}

// ─── Public API ───────────────────────────────────────────────────────────────
export interface StartResult {
  permissionStatus: number;
  motionPermissionStatus?: number;
  blockedReason?: 'location' | 'motion' | 'audio';
  audioError?: string;
  started: boolean;
}

async function requestIosAlwaysLocation(): Promise<number> {
  let provider = await BackgroundGeolocation.getProviderState();
  let permissionStatus = provider.status;

  if (permissionStatus === BackgroundGeolocation.AuthorizationStatus.Always) {
    log('iOS location permission already Always');
    return permissionStatus;
  }

  log('requesting iOS Always location permission');
  permissionStatus = await BackgroundGeolocation.requestPermission().catch(
    () => BackgroundGeolocation.AuthorizationStatus.Denied
  );

  // iOS often grants When In Use first. Ask once more to trigger the Always
  // upgrade path before we decide tracking is blocked.
  if (
    permissionStatus === BackgroundGeolocation.AuthorizationStatus.WhenInUse
  ) {
    log('requesting iOS Always upgrade');
    await sleep(750);
    permissionStatus = await BackgroundGeolocation.requestPermission().catch(
      () => BackgroundGeolocation.AuthorizationStatus.Denied
    );
  }

  provider = await BackgroundGeolocation.getProviderState().catch(
    () => ({ status: permissionStatus }) as any
  );
  return provider.status ?? permissionStatus;
}

async function requestIosMotionPermission(): Promise<number> {
  const sensors = await BackgroundGeolocation.getSensors().catch(() => null);
  if (!sensors?.motionHardware) {
    log('iOS motion hardware unavailable; skipping motion permission gate');
    return IOS_MOTION_STATUS_AUTHORIZED;
  }

  if (sensors.motionAuthorizationStatus === IOS_MOTION_STATUS_AUTHORIZED) {
    log('iOS motion permission already authorized');
    return sensors.motionAuthorizationStatus;
  }

  log('requesting iOS motion permission');
  return BackgroundGeolocation.requestMotionPermission().catch(() => 2);
}

export async function startBackgroundTracking(): Promise<StartResult> {
  log('starting app-level tracking');
  const state = await ensureReady();

  const permissionStatus =
    Platform.OS === 'ios'
      ? await requestIosAlwaysLocation()
      : (await BackgroundGeolocation.getProviderState()).status;

  if (permissionStatus !== BackgroundGeolocation.AuthorizationStatus.Always) {
    log(`tracking blocked — permission=${permissionStatus}`);
    disconnectLocationSocket();
    hooks.onSocketStatus?.('disconnected');
    return { permissionStatus, blockedReason: 'location', started: false };
  }

  const motionPermissionStatus =
    Platform.OS === 'ios'
      ? await requestIosMotionPermission()
      : IOS_MOTION_STATUS_AUTHORIZED;

  if (motionPermissionStatus !== IOS_MOTION_STATUS_AUTHORIZED) {
    log(`tracking blocked — motion permission=${motionPermissionStatus}`);
    disconnectLocationSocket();
    hooks.onSocketStatus?.('disconnected');
    return {
      permissionStatus,
      motionPermissionStatus,
      blockedReason: 'motion',
      started: false,
    };
  }

  // Connect the socket while the app is alive (so it's warm).
  hooks.onSocketStatus?.('connecting');
  connectLocationSocket();
  hooks.onSocketStatus?.('connected');

  startForegroundInterval();

  if (!state.enabled) {
    log('native start()');
    await BackgroundGeolocation.start();
  } else {
    log('native already enabled');
  }

  if (Platform.OS === 'ios') {
    const nativeState = await BackgroundGeolocation.getState();
    log(`live activity ${JSON.stringify(nativeState.liveActivity ?? {})}`);
    log(`tracking audio ${JSON.stringify(nativeState.trackingAudio ?? {})}`);
    if (!nativeState.trackingAudio?.active) {
      const audioError =
        nativeState.trackingAudio?.error ??
        'The iOS playback audio session did not become active.';
      log(`tracking blocked — audio session inactive: ${audioError}`);
      await BackgroundGeolocation.stop();
      stopForegroundInterval();
      disconnectLocationSocket();
      hooks.onSocketStatus?.('disconnected');
      return {
        permissionStatus,
        motionPermissionStatus,
        blockedReason: 'audio',
        audioError,
        started: false,
      };
    }
  }

  // Immediate first fix
  await sendHeartbeatLocation();

  return { permissionStatus, motionPermissionStatus, started: true };
}

export async function stopBackgroundTracking(): Promise<void> {
  log('stopping tracking');
  stopForegroundInterval();
  disconnectLocationSocket();
  hooks.onSocketStatus?.('disconnected');
  lastSocketLocationSentAt = 0;

  if (!readyPromise) return;
  try {
    const state = await BackgroundGeolocation.getState();
    if (state.enabled) await BackgroundGeolocation.stop();
  } catch {
    // cleanup must never throw
  }
}

// ─── Android headless task ────────────────────────────────────────────────────
// Registered at MODULE SCOPE so it's set up as soon as this file is imported,
// exactly like the production app. In the kill-state JS context this connects a
// fresh socket and sends the location.
let headlessRegistered = false;
function registerHeadlessTask(): void {
  if (Platform.OS !== 'android') return;
  if (headlessRegistered) return;
  headlessRegistered = true;

  BackgroundGeolocation.registerHeadlessTask(async (event: HeadlessEvent) => {
    console.log('[BgGeoTest][HEADLESS]', event.name);

    if (event.name === 'heartbeat') {
      await sendHeartbeatLocation(event.params as HeartbeatEvent);
      return;
    }
    if (event.name !== 'location') return;

    const location = event.params as Location;
    if (!location?.coords) return;

    console.log(
      '[BgGeoTest][HEADLESS] 📍',
      location.coords.latitude,
      location.coords.longitude
    );
    await sendLocationUpdate(location, { force: true });
  });
}

// Run immediately on import.
registerHeadlessTask();
