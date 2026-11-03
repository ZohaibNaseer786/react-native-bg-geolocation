# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- CI: Android example build no longer depends on a machine-specific `org.gradle.java.home`; the runner's JDK is used instead.

### Added
- `CHANGELOG.md`, `SECURITY.md`, feature-request issue template, pull-request template.
- OpenSSF Scorecard workflow and Dependabot configuration.

## [0.2.8] - 2026-11-03

### Changed
- README: added project context, kill-state architecture overview and contribution guidance.

## [0.2.7] - 2026-07-09

### Changed
- **iOS:** `continuousLocationUpdates: false` now means *never* run continuous GPS, even while the device is moving (push-only mode). Previously the flag only gated the stationary state. Use this when location is only needed on demand via Location Push.
- **iOS:** `disableStopDetection` (keep-alive) is overridden by `continuousLocationUpdates: false`.

## [0.2.6] - 2026-07-03

### Fixed
- **iOS:** continuous GPS kept running after a moving user stopped. `detectStopMotion` short-circuited on an eagerly-cleared `isMoving` flag, so the stop transition never powered the location manager down. Stop detection now completes and GPS is released after `stopTimeout`.
- **iOS:** entering the moving state now cancels any pending stop-detection timer.

## [0.2.5] - 2026-06-22

### Fixed
- **iOS:** `continuousLocationUpdates: false` left the background location indicator on. All keep-alive start sites (`restoreUpdatingState`, `onSuspend`, `setMoving`, `onMotionChangeSuccess`) now honour the flag.

## [0.2.4] - 2026-06-19

### Added
- **iOS:** `continuousLocationUpdates` config flag (default `true`) to control whether the engine runs continuous GPS, for battery-sensitive apps that rely on Location Push.

## [0.2.3] - 2026-06-12

### Changed
- LICENSE, package metadata and README clarifications.

## [0.2.2] - 2026-06-12

First public release on npm.

### Added
- React Native New Architecture TurboModule (iOS Swift engine + Android Kotlin).
- Foreground / background tracking, motion-based moving ↔ stationary state machine, activity recognition, geofencing, reboot persistence, odometer.
- **iOS Location Push Service Extension** (`CLLocationPushServiceExtension`): server-triggered location capture and upload while the app is force-quit.
- Native delivery pipeline shared by the app and the extension: Socket.IO v4 over `URLSessionWebSocketTask` with REST fallback.
- `setLocationPushConfig` with `payloadTemplate` and `headers` so apps configure the delivery payload from JS without patching native code. Default payload: `{ lat, long, fcm_token, device_type, user_current_time, location_query_id }`.
- `getLocationPushToken`, `getApnsDeviceToken`, `onLocationPush`, `finishLocationPush`.
- iOS Live Activity (Lock Screen / Dynamic Island) tracking status.
- Android Headless JS task for kill-state execution.
- Native engine namespaced as `BG*` (no `TS*` identifiers, keys or region ids remain).

[Unreleased]: https://github.com/ZohaibNaseer786/react-native-bg-geolocation/compare/v0.2.8...HEAD
[0.2.8]: https://github.com/ZohaibNaseer786/react-native-bg-geolocation/compare/v0.2.7...v0.2.8
[0.2.7]: https://github.com/ZohaibNaseer786/react-native-bg-geolocation/compare/v0.2.6...v0.2.7
[0.2.6]: https://github.com/ZohaibNaseer786/react-native-bg-geolocation/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/ZohaibNaseer786/react-native-bg-geolocation/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/ZohaibNaseer786/react-native-bg-geolocation/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/ZohaibNaseer786/react-native-bg-geolocation/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/ZohaibNaseer786/react-native-bg-geolocation/releases/tag/v0.2.2
