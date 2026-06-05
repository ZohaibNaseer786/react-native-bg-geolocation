import Foundation
import CoreMotion

@objc public protocol TSMotionActivitySourceDelegate: AnyObject {
    func activitySource(_ source: TSMotionActivitySource, didUpdate activity: CMMotionActivity)
}

@objc public class TSMotionActivitySource: NSObject {

    @objc public weak var delegate: TSMotionActivitySourceDelegate?
    @objc public var manager: TSMotionActivityManagerAdapter?
    @objc public var queue: OperationQueue?
    @objc private(set) var running: Bool = false

    @objc public class func isAvailable() -> Bool {
        return CMMotionActivityManager.isActivityAvailable()
    }

    @objc public init(queue: OperationQueue) {
        self.queue = queue
        self.manager = TSMotionActivityManagerAdapter()
        super.init()
    }

    @objc public override init() {
        self.queue = OperationQueue()
        self.manager = TSMotionActivityManagerAdapter()
        super.init()
    }

    @objc public func start() {
        guard !running, let mgr = manager, let q = queue else { return }
        running = true
        mgr.startActivityUpdates(toQueue: q) { [weak self] activity in
            guard let self = self, let activity = activity else { return }
            self.delegate?.activitySource(self, didUpdate: activity)
        }
    }

    @objc public func stop() {
        manager?.stopActivityUpdates()
        running = false
    }

    public func setRunning(_ value: Bool) { running = value }
}
