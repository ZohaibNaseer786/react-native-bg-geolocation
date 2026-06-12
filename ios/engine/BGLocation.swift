import Foundation
import CoreLocation
import UIKit

@objc public class BGLocation: NSObject {

    @objc public var location: CLLocation?
    @objc public var uuid: String = UUID().uuidString
    @objc public var event: String = ""
    @objc public var type: String = ""
    @objc public var isMoving: Bool = false
    @objc public var isSample: Bool = false
    @objc public var isHeartbeat: Bool = false
    @objc public var odometer: Double = 0
    @objc public var odometerError: Double = 0
    @objc public var mock: Bool = false
    @objc public var extras: [String: Any]?
    @objc public var config: AnyObject?
    @objc public var geofence: BGGeofence?
    @objc public var geofenceEvent: BGGeofenceEvent?
    @objc public var rawTimestampMs: Int64 = 0
    @objc public var rawRecordedAtMs: Int64 = 0

    private var batteryLevel: Float = 0
    private var batteryIsCharging: Bool = false
    private var activityType: String = "unknown"
    private var activityConfidence: Int = 0
    private var cachedDictionary: [String: Any]?
    private var _uptime: TimeInterval = 0

    @objc public class func isValidCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        return CLLocationCoordinate2DIsValid(coordinate) &&
               coordinate.latitude != 0 &&
               coordinate.longitude != 0
    }

    @objc public class func uptime() -> TimeInterval {
        return ProcessInfo.processInfo.systemUptime
    }

    @objc public override init() {
        super.init()
        setupDefaultValues()
    }

    @objc public init(location: CLLocation) {
        self.location = location
        super.init()
        setupDefaultValues()
        extractLocationData(location)
    }

    @objc public init(location: CLLocation, geofence: BGGeofence) {
        self.location = location
        self.geofence = geofence
        super.init()
        setupDefaultValues()
        extractLocationData(location)
        event = "geofence"
    }

    @objc public init(location: CLLocation, geofenceEvent: BGGeofenceEvent) {
        self.location = location
        self.geofenceEvent = geofenceEvent
        super.init()
        setupDefaultValues()
        extractLocationData(location)
        event = "geofence"
    }

    @objc public init(location: CLLocation, type: String, extras: [String: Any]?) {
        self.location = location
        self.type = type
        self.extras = extras
        super.init()
        setupDefaultValues()
        extractLocationData(location)
    }

    @objc public func setupDefaultValues() {
        _uptime = ProcessInfo.processInfo.systemUptime
        updateDeviceStatus()
    }

    @objc public func configureWithType(_ type: String, extras: [String: Any]?) {
        self.type = type
        self.extras = extras
        invalidateCache()
    }

    @objc public func extractLocationData(_ loc: CLLocation) {
        rawTimestampMs = Int64(loc.timestamp.timeIntervalSince1970 * 1000)
        rawRecordedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
    }

    @objc public func updateDeviceStatus() {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        batteryLevel = device.batteryLevel
        batteryIsCharging = device.batteryState == .charging || device.batteryState == .full
    }

    @objc public func updateActivityData() {
        invalidateCache()
    }

    @objc public func invalidateCache() {
        cachedDictionary = nil
    }

    @objc public func age() -> TimeInterval {
        guard let loc = location else { return 0 }
        return Date().timeIntervalSince(loc.timestamp)
    }

    @objc public func timestamp() -> Date {
        return location?.timestamp ?? Date()
    }

    @objc public func recordedAt() -> Date {
        if rawRecordedAtMs > 0 {
            return Date(timeIntervalSince1970: Double(rawRecordedAtMs) / 1000.0)
        }
        return Date()
    }

    @objc public func isValidCoordinate(_ coord: CLLocationCoordinate2D) -> Bool {
        return BGLocation.isValidCoordinate(coord)
    }

    @objc public func toDictionary() -> [String: Any] {
        if let cached = cachedDictionary { return cached }
        let dict = buildDictionary()
        cachedDictionary = dict
        return dict
    }

    @objc public func buildDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["uuid"] = uuid
        dict["event"] = event.isEmpty ? NSNull() : event
        dict["is_moving"] = isMoving
        dict["odometer"] = odometer

        if let loc = location {
            dict["coords"] = buildCoordinatesDictionary()
            dict["timestamp"] = ISO8601DateFormatter().string(from: loc.timestamp)
        }

        dict["activity"] = activityDictionary()
        dict["battery"] = batteryDictionary()
        dict["timestamp_meta"] = timestampMetaDictionary()

        if mock { dict["mock"] = true }
        if isSample { dict["sample"] = true }

        if let geofenceEvent = geofenceEvent {
            dict["geofence"] = geofenceTemplateData()
        }

        if let extras = extras {
            dict["extras"] = extras
        }

        return dict
    }

    @objc public func buildCoordinatesDictionary() -> [String: Any] {
        guard let loc = location else { return [:] }
        var coords: [String: Any] = [:]
        coords["latitude"] = loc.coordinate.latitude
        coords["longitude"] = loc.coordinate.longitude
        coords["accuracy"] = loc.horizontalAccuracy
        coords["altitude"] = loc.altitude
        coords["altitude_accuracy"] = loc.verticalAccuracy
        coords["heading"] = loc.course
        coords["speed"] = loc.speed
        if let heading = speedAccuracyNumber(loc) { coords["speed_accuracy"] = heading }
        if let headingAccuracy = headingAccuracyNumber(loc) { coords["heading_accuracy"] = headingAccuracy }
        if let ellipsoidal = ellipsoidalAltitudeNumber(loc) { coords["ellipsoidal_altitude"] = ellipsoidal }
        return coords
    }

    @objc public func activityDictionary() -> [String: Any] {
        return ["type": activityType, "confidence": activityConfidence]
    }

    @objc public func batteryDictionary() -> [String: Any] {
        return ["level": batteryLevel, "is_charging": batteryIsCharging]
    }

    @objc public func timestampMetaDictionary() -> [String: Any] {
        var meta: [String: Any] = [:]
        meta["system_time"] = Date().timeIntervalSince1970 * 1000
        meta["system_clock_elapsed"] = ProcessInfo.processInfo.systemUptime * 1000
        if rawTimestampMs > 0 { meta["event_elapsed"] = Double(rawTimestampMs) }
        if rawRecordedAtMs > 0 { meta["recorded_at"] = Double(rawRecordedAtMs) }
        return meta
    }

    @objc public func timestampMetaJSONString() -> String {
        let dict = timestampMetaDictionary()
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    @objc public func geofenceTemplateData() -> [String: Any] {
        guard let event = geofenceEvent else { return [:] }
        return event.toDictionary()
    }

    @objc public func locationTemplateData() -> [String: Any] {
        return toDictionary()
    }

    @objc public func combinedGeofenceExtras() -> [String: Any]? {
        var combined: [String: Any] = [:]
        if let e = extras { combined.merge(e) { $1 } }
        if let ge = geofenceEvent?.extras as? [String: Any] { combined.merge(ge) { $1 } }
        return combined.isEmpty ? nil : combined
    }

    @objc public func toJson(_ error: UnsafeMutablePointer<NSError?>?) -> String? {
        let dict = toDictionary()
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @objc public func serializeClassicFormat(_ error: UnsafeMutablePointer<NSError?>?) -> Data? {
        let dict = toDictionary()
        return try? JSONSerialization.data(withJSONObject: dict)
    }

    @objc public func serializeJSONObject(_ error: UnsafeMutablePointer<NSError?>?) -> Data? {
        let dict = toDictionary()
        return try? JSONSerialization.data(withJSONObject: dict)
    }

    @objc public func renderTemplate(_ template: BGTemplate, error: UnsafeMutablePointer<NSError?>?) -> String? {
        let data = toDictionary()
        let rendered = template.render(with: data)
        guard let jsonData = try? JSONSerialization.data(withJSONObject: rendered) else { return nil }
        return String(data: jsonData, encoding: .utf8)
    }

    @objc public func finalizeTemplateJSON(_ json: String, error: UnsafeMutablePointer<NSError?>?) -> String? {
        return json
    }

    @objc public func handleTemplateError(_ error: Error, template: BGTemplate) {
    }

    @objc public func selectTemplate() -> BGTemplate? {
        return nil
    }

    @objc public func templateName(forTemplate template: BGTemplate) -> String {
        return template.name
    }

    @objc public func processLocation(_ location: CLLocation, error: UnsafeMutablePointer<NSError?>?) -> Bool {
        self.location = location
        extractLocationData(location)
        invalidateCache()
        return true
    }

    @objc public func mergeExtras(_ newExtras: [String: Any]) {
        if extras == nil { extras = [:] }
        extras?.merge(newExtras) { $1 }
        invalidateCache()
    }

    @objc public func applyExtras(toDictionary dict: NSMutableDictionary) {
        guard let extras = extras else { return }
        dict["extras"] = extras
    }

    @objc public func applyExtras(toArray array: NSMutableArray) {
    }

    @objc public func applyExtras(toJSONObject obj: NSMutableDictionary) {
        applyExtras(toDictionary: obj)
    }

    @objc public func errorWithCode(_ code: Int, description: String) -> NSError {
        return NSError(domain: "BGLocation", code: code, userInfo: [NSLocalizedDescriptionKey: description])
    }

    @objc public func roundValue(_ value: Double) -> Double {
        return (value * 10000).rounded() / 10000
    }

    func speedAccuracyNumber(_ loc: CLLocation) -> Double? {
        if #available(iOS 13.4, *) {
            return loc.speedAccuracy >= 0 ? loc.speedAccuracy : nil
        }
        return nil
    }

    func headingAccuracyNumber(_ loc: CLLocation) -> Double? {
        return loc.courseAccuracy >= 0 ? loc.courseAccuracy : nil
    }

    func ellipsoidalAltitudeNumber(_ loc: CLLocation) -> Double? {
        if #available(iOS 15.0, *) {
            return loc.ellipsoidalAltitude
        }
        return nil
    }
}
