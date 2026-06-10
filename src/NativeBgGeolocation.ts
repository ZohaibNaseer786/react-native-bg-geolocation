import { TurboModuleRegistry, type TurboModule } from 'react-native';

type AnyObject = Object;

export interface Spec extends TurboModule {
  addListener(eventName: string): void;
  removeListeners(count: number): void;

  // Core
  ready(
    config: AnyObject,
    success: (state: AnyObject) => void,
    failure: (error: string) => void
  ): void;
  configure(
    config: AnyObject,
    success: (state: AnyObject) => void,
    failure: (error: string) => void
  ): void;
  reset(
    config: AnyObject,
    success: (state: AnyObject) => void,
    failure: (error: string) => void
  ): void;
  setConfig(
    config: AnyObject,
    success: (state: AnyObject) => void,
    failure: (error: string) => void
  ): void;
  getState(
    success: (state: AnyObject) => void,
    failure: (error: string) => void
  ): void;

  // Lifecycle
  start(
    success: (state: AnyObject) => void,
    failure: (error: string) => void
  ): void;
  stop(
    success: (state: AnyObject) => void,
    failure: (error: string) => void
  ): void;
  startSchedule(
    success: (state: AnyObject) => void,
    failure: (error: string) => void
  ): void;
  stopSchedule(
    success: (state: AnyObject) => void,
    failure: (error: string) => void
  ): void;
  startGeofences(
    success: (state: AnyObject) => void,
    failure: (error: string) => void
  ): void;

  // Background task
  beginBackgroundTask(
    success: (taskId: number) => void,
    failure: (error: string) => void
  ): void;
  finish(
    taskId: number,
    success: () => void,
    failure: (error: string) => void
  ): void;

  // Location
  changePace(
    isMoving: boolean,
    success: () => void,
    failure: (error: string) => void
  ): void;
  getCurrentPosition(
    options: AnyObject,
    success: (location: AnyObject) => void,
    failure: (error: AnyObject) => void
  ): void;
  watchPosition(
    options: AnyObject,
    success: () => void,
    failure: (error: string) => void
  ): void;
  stopWatchPosition(
    success: () => void,
    failure: (error: string) => void
  ): void;

  // Permissions
  requestPermission(
    success: (status: number) => void,
    failure: (status: number) => void
  ): void;
  requestMotionPermission(
    success: (status: number) => void,
    failure: (status: number) => void
  ): void;
  requestTemporaryFullAccuracy(
    purpose: string,
    success: (accuracy: number) => void,
    failure: (error: string) => void
  ): void;
  getProviderState(
    success: (state: AnyObject) => void,
    failure: (error: string) => void
  ): void;

  // HTTP & Persistence
  getLocations(
    success: (locations: AnyObject[]) => void,
    failure: (error: string) => void
  ): void;
  getCount(
    success: (count: number) => void,
    failure: (error: string) => void
  ): void;
  destroyLocations(success: () => void, failure: (error: string) => void): void;
  destroyLocation(
    uuid: string,
    success: () => void,
    failure: (error: string) => void
  ): void;
  insertLocation(
    location: AnyObject,
    success: (location: AnyObject) => void,
    failure: (error: string) => void
  ): void;
  sync(
    success: (locations: AnyObject[]) => void,
    failure: (error: string) => void
  ): void;

  // Odometer
  getOdometer(
    success: (value: number) => void,
    failure: (error: string) => void
  ): void;
  setOdometer(
    value: number,
    success: (location: AnyObject) => void,
    failure: (error: string) => void
  ): void;

  // Geofences
  addGeofence(
    config: AnyObject,
    success: () => void,
    failure: (error: string) => void
  ): void;
  addGeofences(
    geofences: AnyObject[],
    success: () => void,
    failure: (error: string) => void
  ): void;
  removeGeofence(
    identifier: string,
    success: () => void,
    failure: (error: string) => void
  ): void;
  removeGeofences(success: () => void, failure: (error: string) => void): void;
  getGeofences(
    success: (geofences: AnyObject[]) => void,
    failure: (error: string) => void
  ): void;
  getGeofence(
    identifier: string,
    success: (geofence: AnyObject) => void,
    failure: (error: string) => void
  ): void;
  geofenceExists(identifier: string, callback: (exists: boolean) => void): void;

  // Logging
  log(level: string, message: string): void;
  setLogLevel(
    value: number,
    success: (state: AnyObject) => void,
    failure: (error: string) => void
  ): void;
  getLog(
    success: (log: string) => void,
    failure: (error: string) => void
  ): void;
  destroyLog(success: () => void, failure: (error: string) => void): void;
  emailLog(
    email: string,
    success: () => void,
    failure: (error: string) => void
  ): void;

  // Utility
  isPowerSaveMode(
    success: (isPowerSaveMode: boolean) => void,
    failure: (error: string) => void
  ): void;
  getSensors(
    success: (sensors: AnyObject) => void,
    failure: (error: string) => void
  ): void;
  getDeviceInfo(
    success: (info: AnyObject) => void,
    failure: (error: string) => void
  ): void;
  // iOS only: the device's location-push APNs token (hex), or null.
  getLocationPushToken(
    success: (token: string | null) => void,
    failure: (error: string) => void
  ): void;
  // iOS only: the device's standard APNs token (hex) for background pushes, or null.
  getApnsDeviceToken(
    success: (token: string | null) => void,
    failure: (error: string) => void
  ): void;
  // iOS only: hand the Location Push Service Extension its delivery config
  // (preferred socket channel + REST fallback details).
  setLocationPushConfig(
    config: AnyObject,
    success: () => void,
    failure: (error: string) => void
  ): void;
  // iOS only: signal that JS finished handling a background location push
  // (so the native completion handler can be invoked).
  finishLocationPush(
    requestId: string,
    success: () => void,
    failure: (error: string) => void
  ): void;
  playSound(soundId: number): void;

  // NOTE: addListener/removeListeners are intentionally NOT declared here.
  // React Native's TurboModule codegen auto-generates them for every module
  // (to support NativeEventEmitter). Declaring them in the spec causes a
  // "redefinition of __hostFunction…_addListener" error on iOS. We implement
  // them natively (no-op) instead.
}

export default TurboModuleRegistry.getEnforcing<Spec>('BgGeolocation');
