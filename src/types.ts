// ─── Core data types ────────────────────────────────────────────────────────

export interface Location {
  uuid: string;
  timestamp: string;
  coords: {
    latitude: number;
    longitude: number;
    accuracy: number;
    altitude: number;
    altitudeAccuracy: number;
    heading: number;
    speed: number;
  };
  activity: {
    type: string;
    confidence: number;
  };
  battery: {
    level: number;
    is_charging: boolean;
  };
  is_moving: boolean;
  odometer: number;
  extras?: Record<string, unknown>;
}

export interface LocationError {
  code: number;
  message?: string;
}

export interface Geofence {
  identifier: string;
  latitude: number;
  longitude: number;
  radius: number;
  notifyOnEntry?: boolean;
  notifyOnExit?: boolean;
  notifyOnDwell?: boolean;
  loiteringDelay?: number;
  extras?: Record<string, unknown>;
}

export interface GeofenceEvent {
  identifier: string;
  action: 'ENTER' | 'EXIT' | 'DWELL';
  location: Location;
}

export interface MotionChangeEvent {
  isMoving: boolean;
  location: Location;
}

export interface HeartbeatEvent {
  location?: Location;
  shakes?: number;
}

export interface HttpEvent {
  status: number;
  responseText: string;
  success: boolean;
}

export interface ProviderChangeEvent {
  status: number;
  enabled: boolean;
  gps: boolean;
  network: boolean;
  accuracyAuthorization: number;
}

export interface ActivityChangeEvent {
  activity: string;
  confidence: number;
}

/** Payload delivered to a headless task: { name, params }. */
export interface HeadlessEvent {
  name: string;
  params: any;
}

/** Subscription returned by every event listener; call `.remove()` to unsubscribe. */
export interface Subscription {
  remove(): void;
}

// ─── Config (nested, matching react-native-background-geolocation) ────────────

export interface GeolocationConfig {
  desiredAccuracy?: number;
  distanceFilter?: number;
  locationUpdateInterval?: number;
  fastestLocationUpdateInterval?: number;
  deferTime?: number;
  activityType?: number;
  useSignificantChangesOnly?: boolean;
  pausesLocationUpdatesAutomatically?: boolean;
  showsBackgroundLocationIndicator?: boolean;
  isMoving?: boolean;
  stopTimeout?: number;
  stopDetectionDelay?: number;
  disableStopDetection?: boolean;
  disableMotionActivityUpdates?: boolean;
  locationAuthorizationRequest?: 'Always' | 'WhenInUse' | 'Any';
  geofenceProximityRadius?: number;
  geofenceInitialTriggerEntry?: boolean;
}

export interface NotificationConfig {
  title?: string;
  text?: string;
  color?: string;
  channelName?: string;
  smallIcon?: string;
  largeIcon?: string;
  priority?: number;
  sticky?: boolean;
  strings?: Record<string, string>;
}

export interface AppConfig {
  stopOnTerminate?: boolean;
  startOnBoot?: boolean;
  enableHeadless?: boolean;
  heartbeatInterval?: number;
  preventSuspend?: boolean;
  foregroundService?: boolean;
  /** iOS 16.2+: show tracking status on the Lock Screen and Dynamic Island. */
  liveActivityEnabled?: boolean;
  liveActivityTitle?: string;
  liveActivitySubtitle?: string;
  /** Minimum seconds between local ActivityKit updates. */
  liveActivityUpdateInterval?: number;
  /** Seconds before the displayed state is marked stale. */
  liveActivityStaleSeconds?: number;
  /** Request an ActivityKit APNs token for server-driven updates. */
  liveActivityPushUpdates?: boolean;
  /**
   * iOS 15+: enable the Location Push Service Extension flow. When the host app
   * registers a location-push token and your server sends an APNs background
   * push to it, iOS wakes the extension to capture and upload one location —
   * even when the app is force-quit. Requires the Apple-approved
   * `com.apple.developer.location.push` entitlement, an App Group shared with
   * the extension, and "Always" location authorization.
   */
  locationPushEnabled?: boolean;
  /** iOS: start an audible audio session while tracking is enabled. */
  trackingAudioEnabled?: boolean;
  /** iOS tracking tone volume from 0.01 through 1.0. */
  trackingAudioVolume?: number;
  /** iOS: mix the tracking sound with other apps instead of interrupting them. */
  trackingAudioMixWithOthers?: boolean;
  notification?: NotificationConfig;
  backgroundPermissionRationale?: {
    title?: string;
    message?: string;
    positiveAction?: string;
    negativeAction?: string;
  };
}

export interface LoggerConfig {
  debug?: boolean;
  logLevel?: number;
  logMaxDays?: number;
}

export interface PersistenceConfig {
  url?: string;
  method?: string;
  headers?: Record<string, string>;
  params?: Record<string, unknown>;
  autoSync?: boolean;
  autoSyncThreshold?: number;
  batchSync?: boolean;
  maxBatchSize?: number;
  maxRecordsToPersist?: number;
  maxDaysToPersist?: number;
  persistMode?: number;
}

export interface LiveActivityState {
  supported: boolean;
  enabled: boolean;
  active: boolean;
  activityId?: string;
  /**
   * ActivityKit APNs token. Send this to your server and use the
   * `<bundle-id>.push-type.liveactivity` APNs topic for remote updates.
   */
  pushToken?: string;
}

export interface TrackingAudioState {
  enabled: boolean;
  requested: boolean;
  active: boolean;
  audible: boolean;
  volume: number;
  /** Audio playback has no iOS runtime permission prompt. */
  permissionRequired?: false;
  /** `notRequired` for playback-only audio. */
  authorizationStatus?: 'notRequired';
  backgroundModeDeclared?: boolean;
  nowPlayingActive?: boolean;
  error?: string;
}

/**
 * Config accepts EITHER the modern nested shape:
 *   { geolocation: {...}, app: {...}, logger: {...}, persistence: {...} }
 * OR a flat shape (legacy) — both are supported by `ready`/`setConfig`.
 */
export interface Config {
  reset?: boolean;
  geolocation?: GeolocationConfig;
  app?: AppConfig;
  logger?: LoggerConfig;
  persistence?: PersistenceConfig;
  // Allow flat keys too for backwards compatibility
  [key: string]: any;
}

export interface State extends Record<string, any> {
  enabled: boolean;
  schedulerEnabled: boolean;
  trackingMode: number;
  odometer: number;
  liveActivity?: LiveActivityState;
  trackingAudio?: TrackingAudioState;
}

export interface DeviceInfo {
  uuid: string;
  model: string;
  platform: string;
  manufacturer: string;
  version: string;
  framework: string;
  frameworkVersion: string;
}

export interface Sensors {
  platform: string;
  accelerometer: boolean;
  gyroscope: boolean;
  magnetometer: boolean;
  motionHardware: boolean;
  motionAuthorizationStatus?: number;
}
