import Foundation

@objc public class TSHeartbeatService: NSObject {

    private static var _sharedInstance: TSHeartbeatService?
    private static let lock = NSLock()

    @objc public var timer: Timer?
    @objc public var callback: ((Any?) -> Void)?

    @objc public class func sharedInstance() -> TSHeartbeatService {
        lock.lock()
        defer { lock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = TSHeartbeatService()
        }
        return _sharedInstance!
    }

    @objc public override init() {
        super.init()
    }

    @objc public var isRunning: Bool {
        return timer != nil && timer!.isValid
    }

    @objc public func startWithInterval(_ interval: TimeInterval, callback: @escaping (Any?) -> Void) {
        stop()
        self.callback = callback
        timer = Timer.scheduledTimer(timeInterval: interval,
                                     target: self,
                                     selector: #selector(onHeartbeat(_:)),
                                     userInfo: nil,
                                     repeats: true)
    }

    @objc public func stop() {
        timer?.invalidate()
        timer = nil
        callback = nil
    }

    @objc public func evaluate() {
        onHeartbeat(timer)
    }

    @objc private func onHeartbeat(_ timer: Timer?) {
        callback?(nil)
    }
}
