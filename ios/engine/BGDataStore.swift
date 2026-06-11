import Foundation
import CoreLocation

@objc public class BGDataStore: NSObject {

    private static var _sharedInstance: BGDataStore?
    private static let lock = NSLock()

    @objc public var persistQueue: DispatchQueue = DispatchQueue(label: "com.transistorsoft.datastore.persist")
    private var lastOdometerLocation: CLLocation?

    @objc public class func sharedInstance() -> BGDataStore {
        lock.lock()
        defer { lock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = BGDataStore()
        }
        return _sharedInstance!
    }

    @objc public override init() {
        super.init()
        initPrivate()
    }

    @objc public func initPrivate() {
        persistQueue = DispatchQueue(label: "com.transistorsoft.datastore.persist")
        loadLastOdometerLocation()
        initLocationListeners()
    }

    @objc public func initLocationListeners() {
    }

    @objc public func persist(_ location: Any?) {
        persistQueue.async {
            self.tryPersist(location, force: false)
        }
    }

    @objc public func tryPersist(_ location: Any?, force: Bool) {
    }

    @objc public func tryPersist(_ location: Any?, request: Any?) {
    }

    @objc public func flush(_ callback: ((Bool) -> Void)?) {
        persistQueue.async {
            callback?(true)
        }
    }

    @objc public func dispatchPersistBlock(_ block: @escaping () -> Void) {
        persistQueue.async(execute: block)
    }

    @objc public func loadLastOdometerLocation() {
        if let data = UserDefaults.standard.data(forKey: "TSLastOdometerLocation"),
           let loc = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CLLocation.self, from: data) {
            lastOdometerLocation = loc
        }
    }

    @objc public func persistLastOdometerLocation(_ location: CLLocation) {
        lastOdometerLocation = location
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: location, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: "TSLastOdometerLocation")
        }
    }

    @objc public func clearLastOdometerLocation() {
        lastOdometerLocation = nil
        UserDefaults.standard.removeObject(forKey: "TSLastOdometerLocation")
    }
}
