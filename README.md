<div align="center">

# react-native-bg-geolocation

**Production-ready background geolocation for React Native apps across foreground, background, Android headless mode, and iOS Location Push Service Extension kill-state delivery.**

[![React Native](https://img.shields.io/badge/React%20Native-0.85+-61DAFB?style=for-the-badge&logo=react&logoColor=111111)](https://reactnative.dev/)
[![TypeScript](https://img.shields.io/badge/TypeScript-ready-3178C6?style=for-the-badge&logo=typescript&logoColor=white)](https://www.typescriptlang.org/)
[![iOS](https://img.shields.io/badge/iOS-15.1+-111111?style=for-the-badge&logo=apple&logoColor=white)](https://developer.apple.com/ios/)
[![Android](https://img.shields.io/badge/Android-background%20tracking-3DDC84?style=for-the-badge&logo=android&logoColor=111111)](https://developer.android.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

[![npm version](https://img.shields.io/npm/v/react-native-bg-geolocation?style=for-the-badge&logo=npm&label=npm)](https://www.npmjs.com/package/react-native-bg-geolocation)
[![npm downloads](https://img.shields.io/npm/dm/react-native-bg-geolocation?style=for-the-badge&logo=npm&label=downloads)](https://www.npmjs.com/package/react-native-bg-geolocation)
[![GitHub stars](https://img.shields.io/github/stars/ZohaibNaseer786/react-native-bg-geolocation?style=for-the-badge&logo=github)](https://github.com/ZohaibNaseer786/react-native-bg-geolocation/stargazers)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-support-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=111111)](https://buymeacoffee.com/zohaibnaseer)

`react-native-bg-geolocation` helps React Native apps collect and deliver reliable location updates with **foreground tracking**, **background tracking**, **geofencing**, **motion detection**, **Socket.IO / REST delivery**, **Android headless JS**, **iOS Live Activity**, and **iOS force-quit location push support**.

**Foreground Tracking | Background Tracking | Kill-State Delivery | Geofencing | Motion Detection | Socket.IO + REST Fallback | iOS Location Push | Android Headless JS**

</div>

> Built with public platform APIs: FusedLocationProvider + Activity Recognition on Android, and CoreLocation + CoreMotion + BGTaskScheduler + CLLocationPushServiceExtension on iOS.

## Features

- ✅ Foreground / background location tracking with OS relaunch-capable events
- ✅ Moving ↔ stationary detection (motion state machine + activity recognition)
- ✅ OS-owned delivery (Android PendingIntent, iOS significant-change + regions)
- ✅ **iOS Location Push Service Extension** — server-triggered location even when the app is force-quit (APNs `location` push → extension captures + uploads natively)
- ✅ iOS Live Activity for Lock Screen and Dynamic Island tracking status
- ✅ Headless JS task (Android) for kill-state JS execution
- ✅ Pluggable delivery: native socket (Socket.IO) → REST fallback, or your own JS handler
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
  <!-- Required for the app-alive background push path (Location Push). -->
  <string>remote-notification</string>
</array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>com.bggeolocation.location-refresh</string>
</array>
```

For the Location Push Service Extension (kill-state), the app and extension also
need the `aps-environment` and `com.apple.developer.location.push` entitlements
and a shared App Group — see [iOS Location Push Service Extension](#ios-location-push-service-extension-kill-state-tracking).

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

#### iOS Location Push Service Extension (kill-state tracking)

This is the production mechanism for getting a location from a **force-quit**
app. Your server sends an APNs push to the device's *location-push token*; iOS
launches a tiny `CLLocationPushServiceExtension` (a **separate process**, no
React Native), which grabs one fix and uploads it — then the app is left
untouched. This is how rideshare / delivery apps keep tracking after the user
swipes the app away.

> **There is no JavaScript in the extension process.** Delivery from a push is
> done **natively** by the SDK (Socket.IO → REST fallback), because on a
> kill-state / background wake the RN bridge is not running and JS event
> listeners would be dropped.

**Two push types, two paths** (your server may send either/both; the device
uses whichever fires):

| App state | Push to send | Wakes | Who delivers |
|---|---|---|---|
| Alive (fg / backgrounded) | `apns-push-type: background`, `content-available: 1` (standard APNs token) | the app | SDK natively, then fires the `locationpush` JS event for awareness |
| **Force-quit** | `apns-push-type: location` to `<bundle-id>.location-query` (location-push token) | the **extension** | SDK natively inside the extension |

The push payload must carry a `location-query` id (any of `location-query`,
`locationQuery`, `location_query`, `locationQueryId`, `queryId`). Its presence
means "report a location now"; it is echoed back in the upload so the server can
correlate.

**1. Request the Apple entitlement** (one-time, ~24–48h):
<https://developer.apple.com/contact/request/location-push-service-extension>.
Once approved, add `com.apple.developer.location.push` to the app entitlements.

**2. Add an App Group** shared by the app and the extension (e.g.
`group.<your-bundle-id>`). The SDK writes its delivery config into this suite so
the separate-process extension can read where/how to upload. Add the same
identifier to both targets' `Info.plist` files:

```xml
<key>BGLocationPushAppGroupIdentifier</key>
<string>group.your.bundle.id</string>
```

**3. Add a Location Push Service Extension target** whose principal class is the
SDK's `BGLocationPushService`. The example app ships a ready-made target and a
script that wires it (`example/ios/add_location_push_target.rb`) — copy that
target, or run the equivalent for your project. The extension's `Info.plist`:

```xml
<key>NSExtension</key>
<dict>
  <key>NSExtensionPointIdentifier</key>
  <string>com.apple.location.push.service</string>
  <key>NSExtensionPrincipalClass</key>
  <string>BGLocationPushService</string>
</dict>
```

**4. Register the location-push token in `AppDelegate`** and ship it to your
server:

```swift
import CoreLocation
// keep a strong ref or the manager is deallocated before the callback
private var locationPushManager: CLLocationManager?

if #available(iOS 15.0, *) {
  let mgr = CLLocationManager()
  locationPushManager = mgr
  mgr.startMonitoringLocationPushes { tokenData, error in
    guard let data = tokenData else { return }
    let token = data.map { String(format: "%02hhx", $0) }.joined()
    UserDefaults.standard.set(token, forKey: "BGLocationManager_locationPushToken")
  }
}
```

Then in JS, after `ready()`:

```ts
const token = await BackgroundGeolocation.getLocationPushToken(); // iOS only, else null
if (token) await myApi.registerLocationPushToken(token); // your endpoint
```

**5. Configure delivery** (where the extension uploads). Call once after
`ready()`:

```ts
await BackgroundGeolocation.setLocationPushConfig({
  socketUrl: 'https://your.server',     // Socket.IO base URL (tried first)
  socketPath: '/socket/location',
  socketEvent: 'location:update',
  socketAuthToken: jwt,                  // sent in the socket CONNECT auth + REST Bearer
  socketTimeout: 8,                      // seconds before falling back to REST
  fallbackUrl: 'https://your.server/api/location/fallback',
  fcmToken,                              // available as the {fcmToken} token
  // Custom HTTP headers for the REST fallback.
  headers: { 'Device-Type': 'ios' },
  // OPTIONAL: define the exact upload shape (socket emit + REST fallback).
  // Values may contain {tokens} the SDK substitutes with live values. Omit to
  // use the built-in default body.
  payloadTemplate: {
    lat: '{latitude}',                   // exact single token → stays numeric
    long: '{longitude}',
    fcm_token: '{fcmToken}',
    device_type: 'ios',                  // literal value, passed through
    user_current_time: '{userCurrentTime}',
    location_query_id: '{queryId}',
  },
});
```

**`payloadTemplate`** lets you ship any payload shape from JS — no native
patching. Tokens (use inside string values): `{latitude}`/`{lat}`,
`{longitude}`/`{long}`, `{accuracy}`, `{speed}`, `{heading}`, `{altitude}`,
`{timestamp}`, `{fcmToken}`, `{queryId}`, `{userCurrentTime}` (local `HH:mm`),
`{deviceType}`. A value that is exactly one token (`'{latitude}'`) keeps its
native type (numbers stay numbers); inline tokens (`'v2-{queryId}'`) interpolate
as strings; nested objects/arrays are supported. Without `payloadTemplate` the
deliverer posts the default body
`{ lat, long, fcm_token, device_type: "ios", user_current_time, location_query_id }`
(applies to both the socket emit and the REST fallback).

**6. App-alive handler (optional).** When the app is alive, the SDK still
delivers natively and emits a `locationpush` event so your JS can react. The
event carries `delivered: true` when native already sent it — **do not re-send**:

```ts
BackgroundGeolocation.onLocationPush(async (event) => {
  if (event.delivered) return; // native already uploaded it
  // fallback: deliver event.location yourself, then:
  await BackgroundGeolocation.finishLocationPush(event.requestId);
});
```

**7. Server.** Send `apns-push-type: location` to the location-push token with
topic `<bundle-id>.location-query` (and/or a `background` push to the standard
APNs token for the app-alive path). Requires "Always" location authorization.

Set `app.locationPushEnabled: true` in your config to signal this flow is in use.

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
| **iOS (OS relaunch)** | Continuous background updates use Core Location. Significant-change and region events can relaunch an app the system terminated. Each native fix is persisted before upload; interrupted HTTP delivery retries on the next wake. After an explicit force-quit, iOS will **not** relaunch via Core Location until the app is reopened. |
| **iOS (force-quit, push-driven)** | Your server sends an APNs `location` push (topic `<bundle-id>.location-query`) to the device's location-push token. iOS launches the **Location Push Service Extension** — a separate process, even when the app is force-quit — which captures one fix and uploads it natively (Socket.IO → REST fallback). See the [Location Push section](#ios-location-push-service-extension-kill-state-tracking). Requires the Apple `location.push` entitlement, an App Group, and "Always" authorization. |

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
- **Events:** `onLocation`, `onMotionChange`, `onActivityChange`, `onHeartbeat`, `onProviderChange`, `onGeofence`, `onEnabledChange`, `onHttp`, `onLocationPush`, …
- **iOS Location Push (kill-state):** `getLocationPushToken`, `getApnsDeviceToken`, `setLocationPushConfig`, `onLocationPush`, `finishLocationPush` — all iOS-only (resolve `null` / no-op on Android)
- **Enums:** `AuthorizationStatus`, `DesiredAccuracy`, `LogLevel`, `NotificationPriority`, `ActivityType`, `PersistMode`, `AccuracyAuthorization`

## Example

The [`example/`](example) app demonstrates app-level tracking, socket delivery, motion detection and a live event log. See `example/src/backgroundLocationService.ts` for the recommended app-level integration pattern.

```sh
yarn
yarn example android   # or: yarn example ios
```

## Support

If this package saves you time, please consider giving the repo a star. It helps
other React Native developers discover the project.

<div align="center">

### Would you like to support me?

[![Follow on GitHub](https://img.shields.io/badge/Follow-@ZohaibNaseer786-181717?style=social&logo=github)](https://github.com/ZohaibNaseer786)
[![GitHub stars](https://img.shields.io/github/stars/ZohaibNaseer786/react-native-bg-geolocation?style=social)](https://github.com/ZohaibNaseer786/react-native-bg-geolocation/stargazers)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-FF813F?style=for-the-badge&logo=buy-me-a-coffee&logoColor=white)](https://buymeacoffee.com/zohaibnaseer)

</div>

## Contributing

- [Development workflow](CONTRIBUTING.md#development-workflow)
- [Sending a pull request](CONTRIBUTING.md#sending-a-pull-request)

## License

[MIT](LICENSE) © Zohaib Naseer and contributors.

---

Made with [create-react-native-library](https://github.com/callstack/react-native-builder-bob)
