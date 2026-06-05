import Foundation

// Global NSString event-name constants (extern NSString * const TSEventName…).

public let TSEventNameLocation = "location"
public let TSEventNameLocationError = "locationerror"
public let TSEventNameHttp = "http"
public let TSEventNameGeofence = "geofence"
public let TSEventNameHeartbeat = "heartbeat"
public let TSEventNameMotionChange = "motionchange"
public let TSEventNameActivityChange = "activitychange"
public let TSEventNameProviderChange = "providerchange"
public let TSEventNameGeofencesChange = "geofenceschange"
public let TSEventNameSchedule = "schedule"
public let TSEventNamePowerSaveChange = "powersavechange"
public let TSEventNameConnectivityChange = "connectivitychange"
public let TSEventNameEnabledChange = "enabledchange"
public let TSEventNameAuthorization = "authorization"
public let TSEventNameCLLocation = "CLLocation"
public let TSEventNameWatchPosition = "watchposition"
public let TSEventNameRPCError = "RPCError"
public let TSEventNameStopMonitoringSignificantLocationChanges = "stopMonitoringSignificantLocationChanges"

public let TSEventBusNameAppResume = "TSAppState.resume"
public let TSEventBusNameAppSuspend = "TSAppState.suspend"
public let TSEventBusNamePersist = "TSLocation.persist"

// Convenience namespace for dot-syntax access to event name constants.
public struct TSEventNames {
    public static let location = TSEventNameLocation
    public static let locationError = TSEventNameLocationError
    public static let http = TSEventNameHttp
    public static let geofence = TSEventNameGeofence
    public static let heartbeat = TSEventNameHeartbeat
    public static let motionChange = TSEventNameMotionChange
    public static let activityChange = TSEventNameActivityChange
    public static let providerChange = TSEventNameProviderChange
    public static let geofencesChange = TSEventNameGeofencesChange
    public static let schedule = TSEventNameSchedule
    public static let powerSaveChange = TSEventNamePowerSaveChange
    public static let connectivityChange = TSEventNameConnectivityChange
    public static let enabledChange = TSEventNameEnabledChange
    public static let authorization = TSEventNameAuthorization
    public static let watchPosition = TSEventNameWatchPosition
    // Composite names used by TSLog and other components
    public static let locationComplete = "locationComplete"
    public static let locationSample = "locationSample"
    public static let geofenceComplete = "geofenceComplete"
    public static let motionChangeComplete = "motionChangeComplete"
    public static let motionChangeError = "motionChangeError"
}
