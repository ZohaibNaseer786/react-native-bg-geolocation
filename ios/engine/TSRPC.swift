import Foundation

@objc public class TSRPCAction: NSObject {

    @objc public var command: String = ""
    @objc public var args: [String: Any]?
    @objc public var callback: String?

    @objc public init(array: [Any]) {
        if array.count > 0 { command = array[0] as? String ?? "" }
        if array.count > 1 { args = array[1] as? [String: Any] }
        if array.count > 2 { callback = array[2] as? String }
        super.init()
    }

    @objc public override init() {
        super.init()
    }

    @objc public override var description: String {
        return "<TSRPCAction command=\(command)>"
    }

    @objc public func ensureArgs(_ key: String) -> Bool {
        return args?[key] != nil
    }

    @objc public func execute(_ locationManager: AnyObject) {
        switch command {
        case "start":
            start(locationManager)
        case "stop":
            stop(locationManager)
        case "changePace":
            changePace(locationManager)
        case "setConfig":
            setConfig(locationManager)
        case "addGeofence":
            addGeofence(locationManager)
        case "addGeofences":
            addGeofences(locationManager)
        case "removeGeofence":
            removeGeofence(locationManager)
        case "removeGeofences":
            removeGeofences(locationManager)
        case "startGeofences":
            startGeofences(locationManager)
        case "startSchedule":
            startSchedule(locationManager)
        case "stopSchedule":
            stopSchedule(locationManager)
        case "setOdometer":
            setOdometer(locationManager)
        case "uploadLog":
            uploadLog(locationManager)
        case "ban":
            ban(locationManager)
        default:
            break
        }
    }

    @objc public func start(_ lm: AnyObject) {
        lm.perform(NSSelectorFromString("start"))
    }

    @objc public func stop(_ lm: AnyObject) {
        lm.perform(NSSelectorFromString("stop"))
    }

    @objc public func changePace(_ lm: AnyObject) {
        guard let isMoving = args?["isMoving"] as? Bool else { return }
        lm.perform(NSSelectorFromString("changePace:"), with: NSNumber(value: isMoving))
    }

    @objc public func setConfig(_ lm: AnyObject) {
        guard let config = args else { return }
        lm.perform(NSSelectorFromString("setConfig:"), with: config)
    }

    @objc public func addGeofence(_ lm: AnyObject) {
        guard let geofence = args else { return }
        lm.perform(NSSelectorFromString("addGeofence:"), with: geofence)
    }

    @objc public func addGeofences(_ lm: AnyObject) {
        guard let geofences = args?["geofences"] as? [[String: Any]] else { return }
        lm.perform(NSSelectorFromString("addGeofences:"), with: geofences)
    }

    @objc public func removeGeofence(_ lm: AnyObject) {
        guard let identifier = args?["identifier"] as? String else { return }
        lm.perform(NSSelectorFromString("removeGeofence:"), with: identifier)
    }

    @objc public func removeGeofences(_ lm: AnyObject) {
        lm.perform(NSSelectorFromString("removeGeofences"))
    }

    @objc public func startGeofences(_ lm: AnyObject) {
        lm.perform(NSSelectorFromString("startGeofences"))
    }

    @objc public func startSchedule(_ lm: AnyObject) {
        lm.perform(NSSelectorFromString("startSchedule"))
    }

    @objc public func stopSchedule(_ lm: AnyObject) {
        lm.perform(NSSelectorFromString("stopSchedule"))
    }

    @objc public func setOdometer(_ lm: AnyObject) {
        guard let value = args?["odometer"] as? Double else { return }
        lm.perform(NSSelectorFromString("setOdometer:"), with: NSNumber(value: value))
    }

    @objc public func uploadLog(_ lm: AnyObject) {
        lm.perform(NSSelectorFromString("uploadLog"))
    }

    @objc public func ban(_ lm: AnyObject) {
    }

    @objc public func buildGeofence(_ dict: [String: Any]) -> TSGeofence? {
        guard let id = dict["identifier"] as? String else { return nil }
        let lat = dict["latitude"] as? Double ?? 0
        let lng = dict["longitude"] as? Double ?? 0
        let radius = dict["radius"] as? Double ?? 200
        let entry = dict["notifyOnEntry"] as? Bool ?? true
        let exit = dict["notifyOnExit"] as? Bool ?? true
        let dwell = dict["notifyOnDwell"] as? Bool ?? false
        let loiteringDelay = dict["loiteringDelay"] as? Double ?? 0
        let extras = dict["extras"] as? [String: Any]
        return TSGeofence.circle(withIdentifier: id, radius: radius, latitude: lat, longitude: lng, notifyOnEntry: entry, notifyOnExit: exit, notifyOnDwell: dwell, loiteringDelay: loiteringDelay, extras: extras)
    }
}

@objc public class TSRPC: NSObject {

    private static var _sharedInstance: TSRPC?
    private static let lock = NSLock()

    @objc public var jsonKey: String = "rpc"
    @objc public var actions: [TSRPCAction] = []

    private let queue = DispatchQueue(label: "TSRPC.queue")

    @objc public class func sharedInstance() -> TSRPC {
        lock.lock()
        defer { lock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = TSRPC()
        }
        return _sharedInstance!
    }

    @objc public override init() {
        super.init()
    }

    @objc public func ingestHTTPResponse(withData data: Data, contentType: String) {
        guard contentType.contains("application/json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rpcArray = json[jsonKey] as? [[Any]] else { return }

        queue.async {
            for item in rpcArray {
                let action = TSRPCAction(array: item)
                self.actions.append(action)
            }
            self.drainLocked()
        }
    }

    @objc public func run(_ action: TSRPCAction) {
        queue.async {
            self.actions.append(action)
            self.drainLocked()
        }
    }

    @objc public func drainLocked() {
        let pending = actions
        actions.removeAll()
        for action in pending {
            NotificationCenter.default.post(name: NSNotification.Name("TSRPCAction"), object: action)
        }
    }

    @objc public func emitRPCError(withCode code: Int, reason: String, userInfo: [String: Any]?) {
        let error = NSError(domain: "TSRPC", code: code, userInfo: [NSLocalizedDescriptionKey: reason])
        NotificationCenter.default.post(name: NSNotification.Name("TSRPCError"), object: error)
    }
}
