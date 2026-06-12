import Foundation

@objc public class BGLocationListener: NSObject {
    @objc public var success: ((Any?) -> Void)?
    @objc public var failure: ((Any?) -> Void)?

    @objc public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? BGLocationListener else { return false }
        return self === other
    }

    @objc public override var hash: Int { return ObjectIdentifier(self).hashValue }
}

@objc public class BGEventManager: NSObject {

    private static var _sharedInstance: BGEventManager?
    private static let lock = NSLock()

    @objc public var listeners: NSMutableDictionary = NSMutableDictionary()
    @objc public var locationListeners: NSMutableArray = NSMutableArray()
    @objc public var bufferedEvents: NSMutableDictionary = NSMutableDictionary()
    @objc public var bufferingEnabled: Bool = true
    @objc public var locked: Bool = false
    @objc public var maxBufferedPerEvent: Int = 1

    @objc public class func sharedInstance() -> BGEventManager {
        lock.lock()
        defer { lock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = BGEventManager()
        }
        return _sharedInstance!
    }

    @objc public override init() {
        super.init()
        listeners = NSMutableDictionary()
        locationListeners = NSMutableArray()
        bufferedEvents = NSMutableDictionary()
        bufferingEnabled = true
        maxBufferedPerEvent = 1
    }

    @objc public func isLocked() -> Bool { return locked }
    @objc public func isBuffering() -> Bool { return bufferingEnabled }

    @objc public func lock() { locked = true }

    @objc public func ready() {
        bufferingEnabled = false
        flushBufferedEvents()
    }

    @objc public func addListener(_ event: String, callback: @escaping (Any?) -> Void) -> String {
        let token = UUID().uuidString
        objc_sync_enter(self)
        var eventListeners = listeners[event] as? [[String: Any]] ?? []
        eventListeners.append(["token": token, "callback": callback])
        listeners[event] = eventListeners
        objc_sync_exit(self)
        return token
    }

    @objc public func addLocationListener(success: @escaping (Any?) -> Void,
                                           failure: @escaping (Any?) -> Void) -> BGLocationListener {
        let listener = BGLocationListener()
        listener.success = success
        listener.failure = failure
        objc_sync_enter(self)
        locationListeners.add(listener)
        objc_sync_exit(self)
        return listener
    }

    @objc public func removeListener(_ event: String, callback: AnyObject) {
        objc_sync_enter(self)
        if var eventListeners = listeners[event] as? [[String: Any]] {
            eventListeners.removeAll { ($0["callback"] as AnyObject) === callback }
            listeners[event] = eventListeners
        }
        objc_sync_exit(self)
    }

    @objc public func removeListener(_ event: String, token: String) {
        objc_sync_enter(self)
        if var eventListeners = listeners[event] as? [[String: Any]] {
            eventListeners.removeAll { ($0["token"] as? String) == token }
            listeners[event] = eventListeners
        }
        objc_sync_exit(self)
    }

    @objc public func removeListeners(_ event: String) {
        objc_sync_enter(self)
        listeners.removeObject(forKey: event)
        objc_sync_exit(self)
    }

    @objc public func removeListeners() {
        objc_sync_enter(self)
        listeners.removeAllObjects()
        locationListeners.removeAllObjects()
        objc_sync_exit(self)
    }

    @objc public func trigger(_ event: String, payload: Any?) {
        if bufferingEnabled {
            bufferEvent(event, payload: payload)
            return
        }
        objc_sync_enter(self)
        let eventListeners = listeners[event] as? [[String: Any]] ?? []
        objc_sync_exit(self)
        for entry in eventListeners {
            if let callback = entry["callback"] as? (Any?) -> Void {
                callback(payload)
            }
        }
    }

    @objc public func triggerLocationSuccess(_ location: Any?) {
        objc_sync_enter(self)
        let lst = locationListeners.copy() as! NSArray
        objc_sync_exit(self)
        for listener in lst {
            (listener as? BGLocationListener)?.success?(location)
        }
    }

    @objc public func triggerLocationError(_ error: Any?) {
        objc_sync_enter(self)
        let lst = locationListeners.copy() as! NSArray
        objc_sync_exit(self)
        for listener in lst {
            (listener as? BGLocationListener)?.failure?(error)
        }
    }

    @objc public func bufferEvent(_ event: String, payload: Any?) {
        objc_sync_enter(self)
        var buf = bufferedEvents[event] as? [Any] ?? []
        buf.append(payload as Any)
        if buf.count > maxBufferedPerEvent {
            buf.removeFirst()
        }
        bufferedEvents[event] = buf
        objc_sync_exit(self)
    }

    @objc public func drainBuffer(forEvent event: String) {
        objc_sync_enter(self)
        let buf = bufferedEvents[event] as? [Any] ?? []
        bufferedEvents.removeObject(forKey: event)
        objc_sync_exit(self)
        for payload in buf {
            trigger(event, payload: payload)
        }
    }

    @objc public func flushBufferedEvents() {
        objc_sync_enter(self)
        let events = (bufferedEvents.allKeys as? [String]) ?? []
        objc_sync_exit(self)
        for event in events {
            drainBuffer(forEvent: event)
        }
    }
}
