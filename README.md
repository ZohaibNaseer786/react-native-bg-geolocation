# react-native-bg-geolocation

Background geolocation tracking for React Native in foreground, background, Android kill state, and eligible iOS OS-managed relaunches, with motion detection (moving/stationary), geofencing, and pluggable delivery (socket / HTTP / headless).

> Educational re-implementation of the `react-native-background-geolocation` API using only public platform APIs (FusedLocationProvider + Activity Recognition on Android, CoreLocation + CoreMotion + BGTaskScheduler on iOS). No proprietary binaries.

## Features

- ✅ Foreground / background location tracking with OS relaunch-capable events
- ✅ Moving ↔ stationary detection (motion state machine + activity recognition)
- ✅ OS-owned delivery (Android PendingIntent, iOS significant-change + regions)
- ✅ iOS Live Activity for Lock Screen and Dynamic Island tracking status
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
  <!-- Required only when app.trackingAudioEnabled is approved and enabled. -->
  <string>audio</string>
  <string>fetch</string>
  <string>processing</string>
</array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>com.bggeolocation.location-refresh</string>
</array>
```

Register the BGTask in `AppDelegate` (see the example app's `AppDelegate.swift`).

#### iOS Live Activity

Live Activities require iOS 16.2 or newer and a WidgetKit extension in the
host application. The example includes a complete extension in
`example/ios/BgGeolocationLiveActivity`.

Add these keys to the app `Info.plist`:

```xml
<key>NSSupportsLiveActivities</key>
<true/>
<key>NSSupportsLiveActivitiesFrequentUpdates</key>
<true/>
```

Add `ios/liveactivity/TSLiveTrackingAttributes.swift` to the WidgetKit
extension target and create an `ActivityConfiguration` for
`TSLiveTrackingAttributes`. The package starts, updates, recovers, and ends the
activity from native iOS location callbacks.

#### iOS Tracking Audio

For Apple-approved use cases, the package can run a real audible audio session
beside Core Location while tracking is active:

```ts
app: {
  trackingAudioEnabled: true,
  trackingAudioVolume: 0.04,
  trackingAudioMixWithOthers: true,
}
```

Audio playback has no iOS runtime permission dialog. The host app must obtain
clear user consent in its own UI before starting it. The app's Start and Stop
actions control both tracking and audio. The package publishes the approved
playback session through Now Playing, where Pause or Stop ends both playback and
tracking. The tracking Live Activity remains a separate status surface. Add
`audio` to `UIBackgroundModes` and enable this only
for an audio use case and distribution model Apple has approved. Explicitly
swiping the app away still terminates audio and location execution.
Runtime status is available from
`(await BackgroundGeolocation.getState()).trackingAudio`.

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
    liveActivityEnabled: true,
    liveActivityTitle: 'Live location',
    liveActivitySubtitle: 'Background tracking is active',
    // Enable only after adding Push Notifications and ActivityKit APNs.
    liveActivityPushUpdates: false,
    trackingAudioEnabled: true,
    trackingAudioVolume: 0.04,
    trackingAudioMixWithOthers: true,
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
| **iOS** | Continuous background updates use Core Location. Significant-change and region events can relaunch an app that the system terminated. Each native fix is persisted before upload, and interrupted HTTP delivery is retried on the next native wake or launch. A Live Activity displays native tracking state and can receive server updates through ActivityKit APNs. If the person explicitly force-quits the app, iOS prevents Core Location relaunch until the app is opened again. |

Live Activities do not collect location and do not provide unrestricted
background execution. Their extension cannot access the network or receive
location updates. Core Location performs tracking; ActivityKit presents the
latest state. For updates while the app process is unavailable, read
`(await BackgroundGeolocation.getState()).liveActivity.pushToken`, send it to
your server, and update the activity through APNs using the
`<bundle-id>.push-type.liveactivity` topic.

Devices without a Dynamic Island, including iPhone 12, show the Live Activity
on the Lock Screen rather than persistently in the status bar.

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
