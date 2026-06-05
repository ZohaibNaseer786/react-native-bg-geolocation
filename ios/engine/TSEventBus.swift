import Foundation

public typealias TSEventBusListener = (_ payload: Any?) -> Void

@objc public class TSEventBus: NSObject {

    private static var _sharedInstance: TSEventBus?
    private static let lock = NSLock()

    @objc public var listenersByEvent: NSMutableDictionary = NSMutableDictionary()
    @objc public var locked: Bool = false
    @objc public var q: DispatchQueue = DispatchQueue(label: "com.transistorsoft.eventbus", attributes: .concurrent)

    @objc public class func sharedInstance() -> TSEventBus {
        lock.lock()
        defer { lock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = TSEventBus()
        }
        return _sharedInstance!
    }

    @objc public func initPrivate() {
        q = DispatchQueue(label: "com.transistorsoft.eventbus", attributes: .concurrent)
        listenersByEvent = NSMutableDictionary()
    }

    @objc public func isLocked() -> Bool { return locked }

    @objc public func lock() { locked = true }

    @objc public func _isOnQueue() -> Bool {
        return false
    }

    @objc public func on(_ event: String, listener: @escaping TSEventBusListener) -> String {
        let token = UUID().uuidString
        q.async(flags: .barrier) {
            var listeners = self.listenersByEvent[event] as? [[String: Any]] ?? []
            listeners.append(["token": token, "listener": listener])
            self.listenersByEvent[event] = listeners
        }
        return token
    }

    @objc public func off(_ event: String, token: String) {
        q.async(flags: .barrier) {
            var listeners = self.listenersByEvent[event] as? [[String: Any]] ?? []
            listeners.removeAll { ($0["token"] as? String) == token }
            self.listenersByEvent[event] = listeners
        }
    }

    @objc public func offAll(_ event: String) {
        q.async(flags: .barrier) {
            self.listenersByEvent.removeObject(forKey: event)
        }
    }

    @objc public func offAll() {
        q.async(flags: .barrier) {
            self.listenersByEvent.removeAllObjects()
        }
    }

    @objc public func emit(_ event: String, payload: Any?) {
        q.sync {
            guard let listeners = self.listenersByEvent[event] as? [[String: Any]] else { return }
            for entry in listeners {
                if let fn = entry["listener"] as? TSEventBusListener {
                    fn(payload)
                }
            }
        }
    }

    @objc public func trigger(_ event: String, payload: Any?) {
        emit(event, payload: payload)
    }

    public func setListenersByEvent(_ dict: NSMutableDictionary) { listenersByEvent = dict }
    public func setLocked(_ val: Bool) { locked = val }
}
