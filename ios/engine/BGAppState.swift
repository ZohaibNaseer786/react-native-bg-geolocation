import Foundation
import UIKit
import CoreLocation

@objc public class BGAppState: NSObject {

    private static var _sharedInstance: BGAppState?
    private static let onceLock = NSLock()

    @objc public var isInBackground: Bool = false
    @objc public var clientReady: Bool = false
    @objc public var didLaunchInBackground: Bool = false
    @objc public var foregroundObserved: Bool = false
    @objc public var flippedToUserInitiated: Bool = false
    @objc public var heuristicResult: String?
    @objc public var heuristicTimerFired: Bool = false
    @objc public var launchClassificationFinalized: Bool = false
    @objc public var resolvingRoot: Bool = false
    @objc public var readyCallbackDelivered: Bool = false
    @objc public var launchTimestamp: Date?
    @objc public var heuristicTimer: Timer?
    @objc public var rootViewController: UIViewController?
    @objc public var readyCallback: (([String: Any]) -> Void)?
    @objc public var pendingRootCallbacks: [[String: Any]] = []

    @objc public class func sharedInstance() -> BGAppState {
        onceLock.lock()
        defer { onceLock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = BGAppState()
        }
        return _sharedInstance!
    }

    @objc public override init() {
        super.init()
        launchTimestamp = Date()
        isInBackground = UIApplication.shared.applicationState == .background
        didLaunchInBackground = isInBackground || UserDefaults.standard.bool(forKey: "BGLocationManager_didLaunchInBackground")
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        cancelHeuristicTimer()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(onDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onWillTerminate),
                                               name: UIApplication.willTerminateNotification, object: nil)
    }

    @objc public func onDidBecomeActive() {
        isInBackground = false
        foregroundObserved = true
        BGTrackingService.sharedInstance().onResume()
    }

    @objc public func onEnterBackground() {
        isInBackground = true
        startHeuristicTimerIfNeeded()
        BGTrackingService.sharedInstance().onSuspend()
    }

    @objc public func onEnterForeground() {
        isInBackground = false
        cancelHeuristicTimer()
    }

    @objc public func onWillTerminate() {
        BGTrackingService.sharedInstance().onAppTerminate()
    }

    @objc public func startHeuristicTimerIfNeeded() {
        guard heuristicTimer == nil else { return }
        heuristicTimer = Timer.scheduledTimer(timeInterval: 0.8,
                                              target: self,
                                              selector: #selector(heuristicTimerFiredAction),
                                              userInfo: nil,
                                              repeats: false)
    }

    @objc private func heuristicTimerFiredAction() {
        heuristicTimerFired = true
        heuristicTimer = nil
    }

    @objc public func cancelHeuristicTimer() {
        heuristicTimer?.invalidate()
        heuristicTimer = nil
    }

    @objc public func ready(_ callback: @escaping ([String: Any]) -> Void) {
        readyCallback = callback
        if readyCallbackDelivered {
            callback([:])
        }
    }

    @objc public func hasBackgroundLocationMode() -> Bool {
        guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            return false
        }
        return modes.contains("location")
    }

    @objc public func hasAnyLocationUsageDescription() -> Bool {
        let keys = ["NSLocationAlwaysUsageDescription",
                    "NSLocationWhenInUseUsageDescription",
                    "NSLocationAlwaysAndWhenInUseUsageDescription"]
        return keys.contains { Bundle.main.object(forInfoDictionaryKey: $0) != nil }
    }

    @objc public func canShowBackgroundLocationIndicator() -> Bool {
        if #available(iOS 13.0, *) {
            return true
        }
        return false
    }

    @objc public func applySafeBackgroundLocationSettings(toManager manager: CLLocationManager,
                                                          showsIndicator: Bool) {
        if #available(iOS 11.0, *) {
            manager.showsBackgroundLocationIndicator = showsIndicator
        }
    }

    @objc public func getRootViewController(_ completion: @escaping (UIViewController?) -> Void) {
        DispatchQueue.main.async {
            completion(self.topPresenter())
        }
    }

    @objc public func topPresenter() -> UIViewController? {
        var top = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
