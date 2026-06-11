import Foundation
import CoreLocation

/// Single delegate for the one shared `CLLocationManager`.
///
/// A `CLLocationManager` has exactly ONE `delegate`. Previously
/// `BGTrackingService`, `BGGeofenceManager`, `BGLocationRequestService` and
/// `BGLocationAuthorization` each assigned `manager.delegate = self`, so whoever
/// ran last silently stole every callback from the others (e.g. starting
/// geofences right after tracking killed all `onLocation`/persist events, and
/// the auth callbacks never reached `BGLocationAuthorization`, so
/// `requestPermission` only resolved on its 20s timeout).
///
/// Routing every callback through this one object lets all four services
/// participate again. Each downstream handler already self-filters (region
/// handlers guard by identifier prefix), so fan-out is safe.
@objc public class BGCLRouter: NSObject, CLLocationManagerDelegate {

    private static var _sharedInstance: BGCLRouter?
    private static let instanceLock = NSLock()

    @objc public class func sharedInstance() -> BGCLRouter {
        instanceLock.lock()
        defer { instanceLock.unlock() }
        if _sharedInstance == nil { _sharedInstance = BGCLRouter() }
        return _sharedInstance!
    }

    private var tracking: BGTrackingService { BGTrackingService.sharedInstance() }
    private var geofences: BGGeofenceManager { BGGeofenceManager.sharedInstance() }
    private var requests: BGLocationRequestService { BGLocationRequestService.sharedInstance() }
    private var authorization: BGLocationAuthorization { BGLocationAuthorization.sharedInstance() }

    // MARK: - Location updates

    @objc public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Always feed the request service: it owns getCurrentPosition sampling
        // and watchPosition streams (no-ops when neither is active).
        requests.locationManager(manager, didUpdateLocations: locations)

        // Tracking owns persist + the `location` event; it also forwards each
        // fix to BGGeofenceManager.setLocation internally. Only when tracking is
        // disabled do we feed geofences directly (geofences-only mode).
        if tracking.isEnabled {
            tracking.locationManager(manager, didUpdateLocations: locations)
        } else if geofences.enabled {
            geofences.locationManager(manager, didUpdateLocations: locations)
        }
    }

    @objc public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        requests.locationManager(manager, didFailWithError: error)
        if tracking.isEnabled {
            tracking.locationManager(manager, didFailWithError: error)
        }
    }

    // MARK: - Authorization

    @available(iOS 14.0, *)
    @objc public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Primary path on iOS 14+. Resolves any in-flight requestPermission().
        authorization.locationManagerDidChangeAuthorization(manager)
    }

    // Legacy path (< iOS 14). On iOS 14+ this is not called.
    @objc public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorization.locationManager(manager, didChangeAuthorization: status)
    }

    // MARK: - Region monitoring (handlers self-filter by identifier)

    @objc public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        geofences.locationManager(manager, didEnterRegion: region)
    }

    @objc public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        // "TSStationary" -> tracking (start-detection); "BGGeofence:" -> geofences.
        tracking.locationManager(manager, didExitRegion: region)
        geofences.locationManager(manager, didExitRegion: region)
    }

    @objc public func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        geofences.locationManager(manager, didStartMonitoringFor: region)
    }

    @objc public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        tracking.locationManager(manager, monitoringDidFailFor: region, withError: error)
        geofences.locationManager(manager, monitoringDidFailFor: region, withError: error)
    }

    // MARK: - Pause / resume

    @objc public func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        tracking.locationManagerDidPauseLocationUpdates(manager)
    }

    @objc public func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        tracking.locationManagerDidResumeLocationUpdates(manager)
    }
}
