import Foundation
import CoreMotion

@objc public class BGMotionActivityManagerAdapter: NSObject {

    @objc public var mgr: CMMotionActivityManager?

    @objc public class func isActivityAvailable() -> Bool {
        return CMMotionActivityManager.isActivityAvailable()
    }

    public class func authorizationStatus() -> CMAuthorizationStatus {
        return CMMotionActivityManager.authorizationStatus()
    }

    @objc public override init() {
        mgr = CMMotionActivityManager()
        super.init()
    }

    @objc public func startActivityUpdates(
        toQueue queue: OperationQueue,
        withHandler handler: @escaping CMMotionActivityHandler
    ) {
        mgr?.startActivityUpdates(to: queue, withHandler: handler)
    }

    @objc public func stopActivityUpdates() {
        mgr?.stopActivityUpdates()
    }

    @objc public func queryActivityStarting(
        fromDate start: Date,
        toDate end: Date,
        toQueue queue: OperationQueue,
        withHandler handler: @escaping CMMotionActivityQueryHandler
    ) {
        mgr?.queryActivityStarting(from: start, to: end, to: queue, withHandler: handler)
    }
}
