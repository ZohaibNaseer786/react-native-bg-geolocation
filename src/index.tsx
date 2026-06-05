import { NativeEventEmitter, AppRegistry } from 'react-native';
import NativeBgGeolocation from './NativeBgGeolocation';
import * as Events from './events';

export type {
  Location,
  LocationError,
  Geofence,
  GeofenceEvent,
  MotionChangeEvent,
  HeartbeatEvent,
  HeadlessEvent,
  HttpEvent,
  ProviderChangeEvent,
  ActivityChangeEvent,
  Subscription,
  Config,
  GeolocationConfig,
  AppConfig,
  LoggerConfig,
  PersistenceConfig,
  NotificationConfig,
  State,
  DeviceInfo,
  Sensors,
} from './types';

export { Events };

const EventEmitter = new NativeEventEmitter(NativeBgGeolocation as any);

const TAG = 'BackgroundGeolocation';

// Log levels
const LOG_LEVEL_OFF = 0;
const LOG_LEVEL_ERROR = 1;
const LOG_LEVEL_WARNING = 2;
const LOG_LEVEL_INFO = 3;
const LOG_LEVEL_DEBUG = 4;
const LOG_LEVEL_VERBOSE = 5;

// Accuracy
const DESIRED_ACCURACY_NAVIGATION = -2;
const DESIRED_ACCURACY_HIGH = -1;
const DESIRED_ACCURACY_MEDIUM = 10;
const DESIRED_ACCURACY_LOW = 100;
const DESIRED_ACCURACY_VERY_LOW = 1000;
const DESIRED_ACCURACY_LOWEST = 3000;

// Authorization status
const AUTHORIZATION_STATUS_NOT_DETERMINED = 0;
const AUTHORIZATION_STATUS_RESTRICTED = 1;
const AUTHORIZATION_STATUS_DENIED = 2;
const AUTHORIZATION_STATUS_ALWAYS = 3;
const AUTHORIZATION_STATUS_WHEN_IN_USE = 4;

// Notification priority
const NOTIFICATION_PRIORITY_DEFAULT = 0;
const NOTIFICATION_PRIORITY_HIGH = 1;
const NOTIFICATION_PRIORITY_LOW = -1;
const NOTIFICATION_PRIORITY_MAX = 2;
const NOTIFICATION_PRIORITY_MIN = -2;

// Activity type
const ACTIVITY_TYPE_OTHER = 1;
const ACTIVITY_TYPE_AUTOMOTIVE_NAVIGATION = 2;
const ACTIVITY_TYPE_FITNESS = 3;
const ACTIVITY_TYPE_OTHER_NAVIGATION = 4;

// Location authorization
const LOCATION_AUTHORIZATION_ALWAYS = 'Always';
const LOCATION_AUTHORIZATION_WHEN_IN_USE = 'WhenInUse';
const LOCATION_AUTHORIZATION_ANY = 'Any';

// Persist mode
const PERSIST_MODE_ALL = 2;
const PERSIST_MODE_LOCATION = 1;
const PERSIST_MODE_GEOFENCE = -1;
const PERSIST_MODE_NONE = 0;

// Accuracy authorization
const ACCURACY_AUTHORIZATION_FULL = 0;
const ACCURACY_AUTHORIZATION_REDUCED = 1;

interface Subscription {
  remove(): void;
}

let eventSubscriptions: Array<{
  event: string;
  subscription: any;
  callback: Function;
}> = [];

const findByEventAndCallback = (event: string, callback: Function) => {
  return (
    eventSubscriptions.find(
      (s) => s.event === event && s.callback === callback
    ) ?? null
  );
};

const removeSubscription = (subscription: any) => {
  const idx = eventSubscriptions.findIndex(
    (s) => s.subscription === subscription
  );
  if (idx !== -1) eventSubscriptions.splice(idx, 1);
};

/**
 * Flatten the modern nested Config shape
 *   { geolocation: {...}, app: {...}, logger: {...}, persistence: {...} }
 * into the flat key/value map the native module consumes.
 * Flat keys passed directly are preserved (legacy support).
 */
const flattenConfig = (
  config: Record<string, any> = {}
): Record<string, any> => {
  const out: Record<string, any> = {};
  const nestedKeys = ['geolocation', 'app', 'logger', 'persistence'];

  // Copy top-level keys — exclude nested section containers but KEEP `reset`
  // so the native ready() can honour it (reset:false avoids wiping persisted
  // TSConfig on kill-state relaunches, which would destroy stopOnTerminate etc.)
  Object.keys(config).forEach((key) => {
    if (!nestedKeys.includes(key)) {
      out[key] = config[key];
    }
  });

  // Spread each nested section onto the flat object
  nestedKeys.forEach((section) => {
    const sub = config[section];
    if (sub && typeof sub === 'object') {
      Object.assign(out, sub);
    }
  });

  return out;
};

const validateConfig = (rawConfig: Record<string, any> = {}) => {
  const config = flattenConfig(rawConfig);

  if (
    config.notificationPriority ||
    config.notificationText ||
    config.notificationTitle ||
    config.notificationChannelName ||
    config.notificationColor ||
    config.notificationSmallIcon ||
    config.notificationLargeIcon
  ) {
    console.warn(
      `[${TAG}] WARNING: notification* fields are deprecated. Use notification: {title, text, ...}`
    );
    config.notification = {
      text: config.notificationText,
      title: config.notificationTitle,
      color: config.notificationColor,
      channelName: config.notificationChannelName,
      smallIcon: config.notificationSmallIcon,
      largeIcon: config.notificationLargeIcon,
      priority: config.notificationPriority,
    };
  }
  return config;
};

const logger = {
  error: (msg: string) => NativeBgGeolocation.log('error', msg),
  warn: (msg: string) => NativeBgGeolocation.log('warn', msg),
  debug: (msg: string) => NativeBgGeolocation.log('debug', msg),
  info: (msg: string) => NativeBgGeolocation.log('info', msg),
  notice: (msg: string) => NativeBgGeolocation.log('notice', msg),
  header: (msg: string) => NativeBgGeolocation.log('header', msg),
  on: (msg: string) => NativeBgGeolocation.log('on', msg),
  off: (msg: string) => NativeBgGeolocation.log('off', msg),
  ok: (msg: string) => NativeBgGeolocation.log('ok', msg),
  getLog: () =>
    new Promise<string>((resolve, reject) =>
      NativeBgGeolocation.getLog(resolve, reject)
    ),
  destroyLog: () =>
    new Promise<void>((resolve, reject) =>
      NativeBgGeolocation.destroyLog(resolve, reject)
    ),
  emailLog: (email: string) =>
    new Promise<void>((resolve, reject) =>
      NativeBgGeolocation.emailLog(email, resolve, reject)
    ),
};

export default class BackgroundGeolocation {
  // ─── Constants ────────────────────────────────────────────────────────────
  static get EVENT_BOOT() {
    return Events.BOOT;
  }
  static get EVENT_TERMINATE() {
    return Events.TERMINATE;
  }
  static get EVENT_LOCATION() {
    return Events.LOCATION;
  }
  static get EVENT_MOTIONCHANGE() {
    return Events.MOTIONCHANGE;
  }
  static get EVENT_HTTP() {
    return Events.HTTP;
  }
  static get EVENT_HEARTBEAT() {
    return Events.HEARTBEAT;
  }
  static get EVENT_PROVIDERCHANGE() {
    return Events.PROVIDERCHANGE;
  }
  static get EVENT_ACTIVITYCHANGE() {
    return Events.ACTIVITYCHANGE;
  }
  static get EVENT_GEOFENCE() {
    return Events.GEOFENCE;
  }
  static get EVENT_GEOFENCESCHANGE() {
    return Events.GEOFENCESCHANGE;
  }
  static get EVENT_ENABLEDCHANGE() {
    return Events.ENABLEDCHANGE;
  }
  static get EVENT_CONNECTIVITYCHANGE() {
    return Events.CONNECTIVITYCHANGE;
  }
  static get EVENT_SCHEDULE() {
    return Events.SCHEDULE;
  }
  static get EVENT_POWERSAVECHANGE() {
    return Events.POWERSAVECHANGE;
  }
  static get EVENT_NOTIFICATIONACTION() {
    return Events.NOTIFICATIONACTION;
  }
  static get EVENT_AUTHORIZATION() {
    return Events.AUTHORIZATION;
  }

  static get LOG_LEVEL_OFF() {
    return LOG_LEVEL_OFF;
  }
  static get LOG_LEVEL_ERROR() {
    return LOG_LEVEL_ERROR;
  }
  static get LOG_LEVEL_WARNING() {
    return LOG_LEVEL_WARNING;
  }
  static get LOG_LEVEL_INFO() {
    return LOG_LEVEL_INFO;
  }
  static get LOG_LEVEL_DEBUG() {
    return LOG_LEVEL_DEBUG;
  }
  static get LOG_LEVEL_VERBOSE() {
    return LOG_LEVEL_VERBOSE;
  }

  static get DESIRED_ACCURACY_NAVIGATION() {
    return DESIRED_ACCURACY_NAVIGATION;
  }
  static get DESIRED_ACCURACY_HIGH() {
    return DESIRED_ACCURACY_HIGH;
  }
  static get DESIRED_ACCURACY_MEDIUM() {
    return DESIRED_ACCURACY_MEDIUM;
  }
  static get DESIRED_ACCURACY_LOW() {
    return DESIRED_ACCURACY_LOW;
  }
  static get DESIRED_ACCURACY_VERY_LOW() {
    return DESIRED_ACCURACY_VERY_LOW;
  }
  static get DESIRED_ACCURACY_LOWEST() {
    return DESIRED_ACCURACY_LOWEST;
  }

  static get AUTHORIZATION_STATUS_NOT_DETERMINED() {
    return AUTHORIZATION_STATUS_NOT_DETERMINED;
  }
  static get AUTHORIZATION_STATUS_RESTRICTED() {
    return AUTHORIZATION_STATUS_RESTRICTED;
  }
  static get AUTHORIZATION_STATUS_DENIED() {
    return AUTHORIZATION_STATUS_DENIED;
  }
  static get AUTHORIZATION_STATUS_ALWAYS() {
    return AUTHORIZATION_STATUS_ALWAYS;
  }
  static get AUTHORIZATION_STATUS_WHEN_IN_USE() {
    return AUTHORIZATION_STATUS_WHEN_IN_USE;
  }

  static get NOTIFICATION_PRIORITY_DEFAULT() {
    return NOTIFICATION_PRIORITY_DEFAULT;
  }
  static get NOTIFICATION_PRIORITY_HIGH() {
    return NOTIFICATION_PRIORITY_HIGH;
  }
  static get NOTIFICATION_PRIORITY_LOW() {
    return NOTIFICATION_PRIORITY_LOW;
  }
  static get NOTIFICATION_PRIORITY_MAX() {
    return NOTIFICATION_PRIORITY_MAX;
  }
  static get NOTIFICATION_PRIORITY_MIN() {
    return NOTIFICATION_PRIORITY_MIN;
  }

  static get ACTIVITY_TYPE_OTHER() {
    return ACTIVITY_TYPE_OTHER;
  }
  static get ACTIVITY_TYPE_AUTOMOTIVE_NAVIGATION() {
    return ACTIVITY_TYPE_AUTOMOTIVE_NAVIGATION;
  }
  static get ACTIVITY_TYPE_FITNESS() {
    return ACTIVITY_TYPE_FITNESS;
  }
  static get ACTIVITY_TYPE_OTHER_NAVIGATION() {
    return ACTIVITY_TYPE_OTHER_NAVIGATION;
  }

  static get LOCATION_AUTHORIZATION_ALWAYS() {
    return LOCATION_AUTHORIZATION_ALWAYS;
  }
  static get LOCATION_AUTHORIZATION_WHEN_IN_USE() {
    return LOCATION_AUTHORIZATION_WHEN_IN_USE;
  }
  static get LOCATION_AUTHORIZATION_ANY() {
    return LOCATION_AUTHORIZATION_ANY;
  }

  static get PERSIST_MODE_ALL() {
    return PERSIST_MODE_ALL;
  }
  static get PERSIST_MODE_LOCATION() {
    return PERSIST_MODE_LOCATION;
  }
  static get PERSIST_MODE_GEOFENCE() {
    return PERSIST_MODE_GEOFENCE;
  }
  static get PERSIST_MODE_NONE() {
    return PERSIST_MODE_NONE;
  }

  static get ACCURACY_AUTHORIZATION_FULL() {
    return ACCURACY_AUTHORIZATION_FULL;
  }
  static get ACCURACY_AUTHORIZATION_REDUCED() {
    return ACCURACY_AUTHORIZATION_REDUCED;
  }

  // ─── Namespaced enums (match react-native-background-geolocation) ───────────
  static get AuthorizationStatus() {
    return {
      NotDetermined: AUTHORIZATION_STATUS_NOT_DETERMINED,
      Restricted: AUTHORIZATION_STATUS_RESTRICTED,
      Denied: AUTHORIZATION_STATUS_DENIED,
      Always: AUTHORIZATION_STATUS_ALWAYS,
      WhenInUse: AUTHORIZATION_STATUS_WHEN_IN_USE,
    } as const;
  }

  static get DesiredAccuracy() {
    return {
      Navigation: DESIRED_ACCURACY_NAVIGATION,
      High: DESIRED_ACCURACY_HIGH,
      Medium: DESIRED_ACCURACY_MEDIUM,
      Low: DESIRED_ACCURACY_LOW,
      VeryLow: DESIRED_ACCURACY_VERY_LOW,
      Lowest: DESIRED_ACCURACY_LOWEST,
    } as const;
  }

  static get LogLevel() {
    return {
      Off: LOG_LEVEL_OFF,
      Error: LOG_LEVEL_ERROR,
      Warning: LOG_LEVEL_WARNING,
      Info: LOG_LEVEL_INFO,
      Debug: LOG_LEVEL_DEBUG,
      Verbose: LOG_LEVEL_VERBOSE,
    } as const;
  }

  static get NotificationPriority() {
    return {
      Default: NOTIFICATION_PRIORITY_DEFAULT,
      High: NOTIFICATION_PRIORITY_HIGH,
      Low: NOTIFICATION_PRIORITY_LOW,
      Max: NOTIFICATION_PRIORITY_MAX,
      Min: NOTIFICATION_PRIORITY_MIN,
    } as const;
  }

  static get ActivityType() {
    return {
      Other: ACTIVITY_TYPE_OTHER,
      AutomotiveNavigation: ACTIVITY_TYPE_AUTOMOTIVE_NAVIGATION,
      Fitness: ACTIVITY_TYPE_FITNESS,
      OtherNavigation: ACTIVITY_TYPE_OTHER_NAVIGATION,
    } as const;
  }

  static get PersistMode() {
    return {
      All: PERSIST_MODE_ALL,
      Location: PERSIST_MODE_LOCATION,
      Geofence: PERSIST_MODE_GEOFENCE,
      None: PERSIST_MODE_NONE,
    } as const;
  }

  static get AccuracyAuthorization() {
    return {
      Full: ACCURACY_AUTHORIZATION_FULL,
      Reduced: ACCURACY_AUTHORIZATION_REDUCED,
    } as const;
  }

  static get logger() {
    return logger;
  }

  // ─── Headless Task ────────────────────────────────────────────────────────
  static registerHeadlessTask(task: Function) {
    AppRegistry.registerHeadlessTask(TAG, () => task as any);
  }

  // ─── Core ─────────────────────────────────────────────────────────────────
  static ready(config: Record<string, any> = {}): Promise<any> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.ready(validateConfig(config), resolve, reject)
    );
  }

  static configure(config: Record<string, any> = {}): Promise<any> {
    console.warn(`[${TAG}] #configure is deprecated. Use #ready`);
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.configure(validateConfig(config), resolve, reject)
    );
  }

  static reset(config: Record<string, any> = {}): Promise<any> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.reset(validateConfig(config), resolve, reject)
    );
  }

  static setConfig(config: Record<string, any>): Promise<any> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.setConfig(validateConfig(config), resolve, reject)
    );
  }

  static getState(): Promise<any> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.getState(resolve, reject)
    );
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────
  static start(): Promise<any> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.start(resolve, reject)
    );
  }

  static stop(): Promise<any> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.stop(resolve, reject)
    );
  }

  static startSchedule(): Promise<any> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.startSchedule(resolve, reject)
    );
  }

  static stopSchedule(): Promise<any> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.stopSchedule(resolve, reject)
    );
  }

  static startGeofences(): Promise<any> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.startGeofences(resolve, reject)
    );
  }

  // ─── Background Task ──────────────────────────────────────────────────────
  static startBackgroundTask(): Promise<number> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.beginBackgroundTask(resolve, reject)
    );
  }

  static stopBackgroundTask(taskId: number): Promise<number> {
    return new Promise((resolve, reject) => {
      if (!taskId) {
        reject(`INVALID_TASK_ID: ${taskId}`);
        return;
      }
      NativeBgGeolocation.finish(taskId, () => resolve(taskId), reject);
    });
  }

  static finish(taskId: number): Promise<number> {
    return BackgroundGeolocation.stopBackgroundTask(taskId);
  }

  // ─── Motion / Location ────────────────────────────────────────────────────
  static changePace(isMoving: boolean): Promise<void> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.changePace(isMoving, resolve, reject)
    );
  }

  static getCurrentPosition(options: Record<string, any> = {}): Promise<any> {
    if (typeof options === 'function') {
      throw `${TAG}#getCurrentPosition requires options {} as first argument`;
    }
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.getCurrentPosition(options, resolve, reject)
    );
  }

  static watchPosition(
    success: Function,
    failure?: Function,
    options: Record<string, any> = {}
  ): void {
    if (!success) {
      throw `${TAG}#watchPosition cannot use Promises — supply a callback`;
    }
    const cb = () => EventEmitter.addListener('watchposition', success as any);
    NativeBgGeolocation.watchPosition(
      options,
      cb,
      (failure ?? (() => {})) as (error: string) => void
    );
  }

  static stopWatchPosition(): Promise<void> {
    return new Promise((resolve, reject) => {
      EventEmitter.removeAllListeners('watchposition');
      NativeBgGeolocation.stopWatchPosition(resolve, reject);
    });
  }

  // ─── Permissions ──────────────────────────────────────────────────────────
  static requestPermission(): Promise<number> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.requestPermission(resolve, reject)
    );
  }

  static requestTemporaryFullAccuracy(purpose: string): Promise<number> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.requestTemporaryFullAccuracy(purpose, resolve, reject)
    );
  }

  static getProviderState(): Promise<any> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.getProviderState(resolve, reject)
    );
  }

  // ─── HTTP & Persistence ───────────────────────────────────────────────────
  static getLocations(): Promise<any[]> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.getLocations(resolve, reject)
    );
  }

  static getCount(): Promise<number> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.getCount(resolve, reject)
    );
  }

  static destroyLocations(): Promise<void> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.destroyLocations(resolve, reject)
    );
  }

  static destroyLocation(uuid: string): Promise<void> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.destroyLocation(uuid, resolve, reject)
    );
  }

  static insertLocation(location: Record<string, any>): Promise<any> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.insertLocation(location, resolve, reject)
    );
  }

  static sync(): Promise<any[]> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.sync(resolve, reject)
    );
  }

  // ─── Odometer ─────────────────────────────────────────────────────────────
  static getOdometer(): Promise<number> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.getOdometer(resolve, reject)
    );
  }

  static setOdometer(value: number): Promise<any> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.setOdometer(value, resolve, reject)
    );
  }

  static resetOdometer(): Promise<any> {
    return BackgroundGeolocation.setOdometer(0);
  }

  // ─── Geofences ────────────────────────────────────────────────────────────
  static addGeofence(config: Record<string, any>): Promise<void> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.addGeofence(config, resolve, reject)
    );
  }

  static addGeofences(geofences: Record<string, any>[]): Promise<void> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.addGeofences(geofences, resolve, reject)
    );
  }

  static removeGeofence(identifier: string): Promise<void> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.removeGeofence(identifier, resolve, reject)
    );
  }

  static removeGeofences(): Promise<void> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.removeGeofences(resolve, reject)
    );
  }

  static getGeofences(): Promise<any[]> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.getGeofences(resolve, reject)
    );
  }

  static getGeofence(identifier: string): Promise<any> {
    return new Promise((resolve, reject) => {
      if (!identifier) {
        reject(`Invalid identifier: ${identifier}`);
        return;
      }
      NativeBgGeolocation.getGeofence(identifier, resolve, reject);
    });
  }

  static geofenceExists(identifier: string): Promise<boolean> {
    return new Promise((resolve, reject) => {
      if (!identifier) {
        reject(`Invalid identifier: ${identifier}`);
        return;
      }
      NativeBgGeolocation.geofenceExists(identifier, resolve);
    });
  }

  // ─── Event Listeners ──────────────────────────────────────────────────────
  static addListener(
    event: string,
    success: Function,
    failure?: Function
  ): Subscription {
    if (typeof event !== 'string')
      throw `${TAG}#addListener: event must be a string`;
    const handler = (response: any) => {
      if (response?.error != null) {
        if (typeof failure === 'function') failure(response.error);
        else success(response);
      } else {
        success(response);
      }
    };
    const subscription = EventEmitter.addListener(event, handler);
    const originalRemove = subscription.remove.bind(subscription);
    subscription.remove = () => {
      originalRemove();
      removeSubscription(subscription);
    };
    eventSubscriptions.push({ event, subscription, callback: success });
    return subscription;
  }

  static on(
    event: string,
    success: Function,
    failure?: Function
  ): Subscription {
    return BackgroundGeolocation.addListener(event, success, failure);
  }

  static removeListener(event: string, callback: Function): void {
    const found = findByEventAndCallback(event, callback);
    if (found) found.subscription.remove();
  }

  static un(event: string, callback: Function): void {
    BackgroundGeolocation.removeListener(event, callback);
  }

  static removeListeners(): Promise<void> {
    return new Promise((resolve) => {
      eventSubscriptions.forEach((s) => s.subscription.remove());
      eventSubscriptions = [];
      resolve();
    });
  }

  static removeAllListeners(): Promise<void> {
    return BackgroundGeolocation.removeListeners();
  }

  // ─── Typed event helpers ──────────────────────────────────────────────────
  static onLocation(success: Function, failure?: Function): Subscription {
    return BackgroundGeolocation.addListener(Events.LOCATION, success, failure);
  }

  static onMotionChange(callback: Function): Subscription {
    return BackgroundGeolocation.addListener(Events.MOTIONCHANGE, callback);
  }

  static onHttp(callback: Function): Subscription {
    return BackgroundGeolocation.addListener(Events.HTTP, callback);
  }

  static onHeartbeat(callback: Function): Subscription {
    return BackgroundGeolocation.addListener(Events.HEARTBEAT, callback);
  }

  static onProviderChange(callback: Function): Subscription {
    return BackgroundGeolocation.addListener(Events.PROVIDERCHANGE, callback);
  }

  static onActivityChange(callback: Function): Subscription {
    return BackgroundGeolocation.addListener(Events.ACTIVITYCHANGE, callback);
  }

  static onGeofence(callback: Function): Subscription {
    return BackgroundGeolocation.addListener(Events.GEOFENCE, callback);
  }

  static onGeofencesChange(callback: Function): Subscription {
    return BackgroundGeolocation.addListener(Events.GEOFENCESCHANGE, callback);
  }

  static onSchedule(callback: Function): Subscription {
    return BackgroundGeolocation.addListener(Events.SCHEDULE, callback);
  }

  static onEnabledChange(callback: Function): Subscription {
    return BackgroundGeolocation.addListener(Events.ENABLEDCHANGE, callback);
  }

  static onConnectivityChange(callback: Function): Subscription {
    return BackgroundGeolocation.addListener(
      Events.CONNECTIVITYCHANGE,
      callback
    );
  }

  static onPowerSaveChange(callback: Function): Subscription {
    return BackgroundGeolocation.addListener(Events.POWERSAVECHANGE, callback);
  }

  static onNotificationAction(callback: Function): Subscription {
    return BackgroundGeolocation.addListener(
      Events.NOTIFICATIONACTION,
      callback
    );
  }

  static onAuthorization(callback: Function): Subscription {
    return BackgroundGeolocation.addListener(Events.AUTHORIZATION, callback);
  }

  // ─── Logging / Debug ──────────────────────────────────────────────────────
  static setLogLevel(value: number): Promise<any> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.setConfig({ logLevel: value }, resolve, reject)
    );
  }

  static getLog(): Promise<string> {
    return logger.getLog();
  }

  static destroyLog(): Promise<void> {
    return logger.destroyLog();
  }

  static emailLog(email: string): Promise<void> {
    return logger.emailLog(email);
  }

  // ─── Utility ──────────────────────────────────────────────────────────────
  static isPowerSaveMode(): Promise<boolean> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.isPowerSaveMode(resolve, reject)
    );
  }

  static getSensors(): Promise<any> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.getSensors(resolve, reject)
    );
  }

  static getDeviceInfo(): Promise<any> {
    return new Promise((resolve, reject) =>
      NativeBgGeolocation.getDeviceInfo(resolve, reject)
    );
  }

  static playSound(soundId: number): void {
    NativeBgGeolocation.playSound(soundId);
  }
}
