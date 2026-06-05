# react-native-bg-geolocation

Background geolocation tracking for React Native — foreground, background, and **kill state** — with motion detection (moving/stationary), geofencing, and pluggable delivery (socket / HTTP / headless).

> Educational re-implementation of the `react-native-background-geolocation` API using only public platform APIs (FusedLocationProvider + Activity Recognition on Android, CoreLocation + CoreMotion + BGTaskScheduler on iOS). No proprietary binaries.

## Features

- ✅ Foreground / background / **kill-state** location tracking
- ✅ Moving ↔ stationary detection (motion state machine + activity recognition)
- ✅ OS-owned location delivery that survives app kill (Android PendingIntent, iOS significant-change + visits)
- ✅ Headless JS task (Android) for kill-state JS execution
- ✅ Geofencing (`CLCircularRegion` / `GeofencingClient`)
- ✅ Reboot persistence
- ✅ Same API shape as `react-native-background-geolocation` (`AuthorizationStatus`, `DesiredAccuracy`, nested `Config`, etc.)

## Installation

```sh
npm install react-native-bg-geolocation
# or
yarn add react-native-bg-geolocation
```

### iOS

Add to `Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Used to track your location.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Used to track your location in the background.</string>
<key>NSMotionUsageDescription</key>
<string>Used to detect movement.</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>fetch</string>
  <string>processing</string>
</array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>com.bggeolocation.location-refresh</string>
</array>
```

Register the BGTask in `AppDelegate` (see the example app's `AppDelegate.swift`).

### Android

Permissions are declared by the library manifest (`ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE_LOCATION`, `ACTIVITY_RECOGNITION`, `WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`). Request the runtime permissions in JS (see the example).

## Usage

```ts
import BackgroundGeolocation from 'react-native-bg-geolocation';

// 1. Configure (nested config, same shape as the original library)
await BackgroundGeolocation.ready({
  geolocation: {
    desiredAccuracy: BackgroundGeolocation.DesiredAccuracy.High,
    distanceFilter: 10,
    stopTimeout: 5,
    locationAuthorizationRequest: 'Always',
  },
  app: {
    stopOnTerminate: false,
    startOnBoot: true,
    enableHeadless: true,
    heartbeatInterval: 60,
    foregroundService: true,
    notification: { title: 'Tracking', text: 'Location is active' },
  },
  logger: { logLevel: BackgroundGeolocation.LogLevel.Verbose },
});

// 2. Listen
const sub = BackgroundGeolocation.onLocation(location => {
  console.log('[location]', location.coords.latitude, location.coords.longitude);
});
BackgroundGeolocation.onMotionChange(event => {
  console.log('[motionchange]', event.isMoving ? 'moving' : 'stationary');
});

// 3. Request permission + start
const status = await BackgroundGeolocation.requestPermission();
if (status === BackgroundGeolocation.AuthorizationStatus.Always) {
  await BackgroundGeolocation.start();
}

// 4. Cleanup
sub.remove();
await BackgroundGeolocation.stop();
```

### Headless task (Android kill state)

Register at module scope (e.g. in `index.js`) so it survives app kill:

```ts
import BackgroundGeolocation from 'react-native-bg-geolocation';

const headlessTask = async (event) => {
  if (event.name === 'location') {
    const { coords } = event.params;
    // POST to your server with fetch(), connect a socket, etc.
  }
};

BackgroundGeolocation.registerHeadlessTask(headlessTask);
```

## How kill-state delivery works

| Platform | Mechanism |
|---|---|
| **Android** | A FusedLocation `PendingIntent` is owned by the OS and delivered to a `BroadcastReceiver` even when the process is dead. A `START_STICKY` foreground service keeps the process priority high; `onTaskRemoved` reschedules it via `AlarmManager`. Kill-state events fire the **HeadlessJsTask**, where your JS runs. |
| **iOS** | `startMonitoringSignificantLocationChanges` + `startMonitoringVisits` wake the app from kill state; `BGTaskScheduler` provides periodic refresh. `AppDelegate` re-arms monitoring before the bridge loads. |

## API

- **Lifecycle:** `ready`, `start`, `stop`, `getState`, `setConfig`, `reset`
- **Location:** `getCurrentPosition`, `watchPosition`, `stopWatchPosition`, `changePace`, `getOdometer`, `setOdometer`, `resetOdometer`
- **Permissions:** `requestPermission`, `requestTemporaryFullAccuracy`, `getProviderState`
- **Persistence:** `getLocations`, `getCount`, `destroyLocations`, `insertLocation`, `sync`
- **Geofencing:** `addGeofence(s)`, `removeGeofence(s)`, `getGeofences`, `getGeofence`, `geofenceExists`
- **Events:** `onLocation`, `onMotionChange`, `onActivityChange`, `onHeartbeat`, `onProviderChange`, `onGeofence`, `onEnabledChange`, `onHttp`, …
- **Enums:** `AuthorizationStatus`, `DesiredAccuracy`, `LogLevel`, `NotificationPriority`, `ActivityType`, `PersistMode`, `AccuracyAuthorization`

## Example

The [`example/`](example) app demonstrates app-level tracking, socket delivery, motion detection and a live event log. See `example/src/backgroundLocationService.ts` for the recommended app-level integration pattern.

```sh
yarn
yarn example android   # or: yarn example ios
```

## Contributing

- [Development workflow](CONTRIBUTING.md#development-workflow)
- [Sending a pull request](CONTRIBUTING.md#sending-a-pull-request)

## License

MIT

---

Made with [create-react-native-library](https://github.com/callstack/react-native-builder-bob)
