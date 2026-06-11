import Foundation

// Global NSString event-name constants (extern NSString * const BGEventName…).

public let BGEventNameLocation = "location"
public let BGEventNameLocationError = "locationerror"
public let BGEventNameHttp = "http"
public let BGEventNameGeofence = "geofence"
public let BGEventNameHeartbeat = "heartbeat"
public let BGEventNameMotionChange = "motionchange"
public let BGEventNameActivityChange = "activitychange"
public let BGEventNameProviderChange = "providerchange"
public let BGEventNameGeofencesChange = "geofenceschange"
public let BGEventNameSchedule = "schedule"
public let BGEventNamePowerSaveChange = "powersavechange"
public let BGEventNameConnectivityChange = "connectivitychange"
public let BGEventNameEnabledChange = "enabledchange"
public let BGEventNameAuthorization = "authorization"
public let BGEventNameCLLocation = "CLLocation"
public let BGEventNameWatchPosition = "watchposition"
public let BGEventNameRPCError = "RPCError"
public let BGEventNameStopMonitoringSignificantLocationChanges = "stopMonitoringSignificantLocationChanges"

public let BGEventBusNameAppResume = "BGAppState.resume"
public let BGEventBusNameAppSuspend = "BGAppState.suspend"
public let BGEventBusNamePersist = "BGLocation.persist"

// Convenience namespace for dot-syntax access to event name constants.
public struct BGEventNames {
    public static let location = BGEventNameLocation
    public static let locationError = BGEventNameLocationError
    public static let http = BGEventNameHttp
    public static let geofence = BGEventNameGeofence
    public static let heartbeat = BGEventNameHeartbeat
    public static let motionChange = BGEventNameMotionChange
    public static let activityChange = BGEventNameActivityChange
    public static let providerChange = BGEventNameProviderChange
    public static let geofencesChange = BGEventNameGeofencesChange
    public static let schedule = BGEventNameSchedule
    public static let powerSaveChange = BGEventNamePowerSaveChange
    public static let connectivityChange = BGEventNameConnectivityChange
    public static let enabledChange = BGEventNameEnabledChange
    public static let authorization = BGEventNameAuthorization
    public static let watchPosition = BGEventNameWatchPosition
    // Composite names used by BGLog and other components
    public static let locationComplete = "locationComplete"
    public static let locationSample = "locationSample"
    public static let geofenceComplete = "geofenceComplete"
    public static let motionChangeComplete = "motionChangeComplete"
    public static let motionChangeError = "motionChangeError"
}
