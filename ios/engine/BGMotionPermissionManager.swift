import Foundation
import CoreMotion

@objc public class BGMotionPermissionManager: NSObject {

    private static var _sharedInstance: BGMotionPermissionManager?
    private static let lock = NSLock()

    private let motionManager = CMMotionActivityManager()

    @objc public class func sharedInstance() -> BGMotionPermissionManager {
        lock.lock()
        defer { lock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = BGMotionPermissionManager()
        }
        return _sharedInstance!
    }

    @objc public override init() {
        super.init()
    }

    public class func authorizationStatus() -> CMAuthorizationStatus {
        return CMMotionActivityManager.authorizationStatus()
    }

    public func requestPermission(completion: @escaping (_ status: CMAuthorizationStatus) -> Void) {
        motionManager.queryActivityStarting(from: Date(), to: Date(), to: .main) { _, _ in
            completion(CMMotionActivityManager.authorizationStatus())
            self.motionManager.stopActivityUpdates()
        }
    }

    @objc public func isAuthorized() -> Bool {
        return CMMotionActivityManager.authorizationStatus() == .authorized
    }

    @objc public func isDenied() -> Bool {
        return CMMotionActivityManager.authorizationStatus() == .denied
    }

    @objc public func isRestricted() -> Bool {
        return CMMotionActivityManager.authorizationStatus() == .restricted
    }

    @objc public func notDetermined() -> Bool {
        return CMMotionActivityManager.authorizationStatus() == .notDetermined
    }
}
