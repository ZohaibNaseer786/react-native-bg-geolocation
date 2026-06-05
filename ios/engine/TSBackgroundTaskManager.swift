import Foundation
import UIKit
import CoreLocation

@objc public class TSBackgroundTaskManager: NSObject, CLLocationManagerDelegate {

    private static var _sharedInstance: TSBackgroundTaskManager?
    private static let lock = NSLock()

    public var backgroundTasks: [UIBackgroundTaskIdentifier] = []
    public var preventSuspendTasks: [UIBackgroundTaskIdentifier] = []
    @objc public var locationManager: CLLocationManager?
    @objc public var preventSuspendTimer: Timer?
    @objc public var acquisitionBufferTimer: Timer?

    @objc public class func sharedInstance() -> TSBackgroundTaskManager {
        lock.lock()
        defer { lock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = TSBackgroundTaskManager()
        }
        return _sharedInstance!
    }

    @objc public override init() {
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopPreventSuspendTimer()
    }

    @objc public func acquireBackgroundTime() {
        let task = UIApplication.shared.beginBackgroundTask(expirationHandler: { [weak self] in
            self?.stopKeepAlive()
        })
        if task != .invalid {
            backgroundTasks.append(task)
        }
    }

    @objc public func createBackgroundTask() -> UIBackgroundTaskIdentifier {
        return UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
    }

    @objc public func stopBackgroundTask(_ task: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(task)
        backgroundTasks.removeAll { $0 == task }
    }

    @objc public func startKeepAlive() {
        acquireBackgroundTime()
    }

    @objc public func stopKeepAlive() {
        for task in backgroundTasks {
            UIApplication.shared.endBackgroundTask(task)
        }
        backgroundTasks.removeAll()
    }

    @objc public func startPreventSuspend(_ task: UIBackgroundTaskIdentifier) {
        preventSuspendTasks.append(task)
    }

    @objc public func stopPreventSuspend(_ task: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(task)
        preventSuspendTasks.removeAll { $0 == task }
    }

    @objc public func startPreventSuspendTimer(_ interval: TimeInterval) {
        stopPreventSuspendTimer()
        preventSuspendTimer = Timer.scheduledTimer(timeInterval: interval,
                                                   target: self,
                                                   selector: #selector(onPreventSuspendTimer),
                                                   userInfo: nil,
                                                   repeats: true)
    }

    @objc public func stopPreventSuspendTimer() {
        preventSuspendTimer?.invalidate()
        preventSuspendTimer = nil
    }

    @objc public func onPreventSuspendTimer() {
        pleaseStayAwake()
    }

    @objc public func pleaseStayAwake() {
    }

    @objc public func onResume(_ notification: Notification) {
    }

    @objc public func onSuspend(_ notification: Notification) {
    }

    @objc public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    @objc public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    @objc public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {}
}
