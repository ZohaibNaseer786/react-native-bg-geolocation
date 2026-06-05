import Foundation
import CoreLocation
import UIKit

@objc public protocol TSLocationAuthorizationDelegate: NSObjectProtocol {
    @objc optional func locationAuthorization(_ authorization: TSLocationAuthorization, didChangeAuthorizationStatus status: CLAuthorizationStatus)
    @objc optional func locationAuthorization(_ authorization: TSLocationAuthorization, didCompleteWith status: CLAuthorizationStatus, error: Error?)
}

@objc public class TSLocationAuthorization: NSObject, CLLocationManagerDelegate {

    private static var _sharedInstance: TSLocationAuthorization?
    private static let instanceLock = NSLock()

    @objc public class func sharedInstance() -> TSLocationAuthorization {
        instanceLock.lock()
        defer { instanceLock.unlock() }
        if _sharedInstance == nil { _sharedInstance = TSLocationAuthorization() }
        return _sharedInstance!
    }

    @objc public class func configureShared(withLocationManager manager: CLLocationManager) {
        sharedInstance().locationManager = manager
        manager.delegate = sharedInstance()
    }

    // MARK: - State

    @objc public var locationManager: CLLocationManager?
    @objc public weak var delegate: TSLocationAuthorizationDelegate?
    @objc public var enabled: Bool = true
    @objc public var automaticPromptEnabled: Bool = true
    @objc public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @objc public var accuracyAuthorization: Int = 0
    @objc public var desiredPolicy: String = "Always"
    @objc public var pendingPolicy: String = ""
    @objc public var hasPendingPolicy: Bool = false
    @objc public var state: String = "idle"
    @objc public var authorizationTimeoutInterval: TimeInterval = 20.0
    @objc public var currentAlert: UIAlertController?
    public var pendingCompletion: ((CLAuthorizationStatus, Error?) -> Void)?
    public var pendingCompletions: [((CLAuthorizationStatus, Error?) -> Void)] = []
    @objc public var timeoutTimer: Timer?

    @objc public override init() {
        super.init()
        authorizationStatus = CLLocationManager.authorizationStatus()
        registerForApplicationNotifications()
    }

    @objc public init(locationManager: CLLocationManager) {
        self.locationManager = locationManager
        super.init()
        authorizationStatus = CLLocationManager.authorizationStatus()
        locationManager.delegate = self
        registerForApplicationNotifications()
    }

    @objc public func registerForApplicationNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    // MARK: - Authorization checks

    @objc public func isAuthorized() -> Bool {
        return authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    @objc public func isAuthorizedAlways() -> Bool {
        return authorizationStatus == .authorizedAlways
    }

    @objc public func isAuthorizedForPolicy(_ policy: String) -> Bool {
        if policy == "Always" {
            return authorizationStatus == .authorizedAlways
        }
        return isAuthorized()
    }

    @objc public func isAuthorizedForDesiredLocationRequest() -> Bool {
        return isAuthorizedForPolicy(desiredPolicy)
    }

    @objc public func isRequestInProgress() -> Bool {
        return state != "idle"
    }

    @objc public func canRequestAlwaysUpgrade() -> Bool {
        return authorizationStatus == .authorizedWhenInUse
    }

    @objc public func shouldAttemptAlwaysUpgrade() -> Bool {
        return canRequestAlwaysUpgrade() && desiredPolicy == "Always"
    }

    @objc public func effectivePolicy() -> String {
        return desiredPolicy
    }

    @objc public func updateDesiredPolicyFromConfig() {
        let config = TSConfig.sharedInstance()
        desiredPolicy = config.geolocation.locationAuthorizationRequest
    }

    // MARK: - Authorization flow

    @objc public func requestAuthorization(_ completion: ((CLAuthorizationStatus, Error?) -> Void)?) {
        requestAuthorizationForPolicy(desiredPolicy, completion: completion)
    }

    @objc public func requestAuthorizationForPolicy(_ policy: String, completion: ((CLAuthorizationStatus, Error?) -> Void)?) {
        guard enabled else {
            completion?(authorizationStatus, nil)
            return
        }

        if isAuthorizedForPolicy(policy) {
            completion?(authorizationStatus, nil)
            return
        }

        if let c = completion { pendingCompletions.append(c) }
        pendingPolicy = policy

        beginAuthorizationFlow()
    }

    @objc public func requestLocationAuthorization(_ policy: String) {
        requestLocationAuthorization(policy, onCancel: nil)
    }

    @objc public func requestLocationAuthorization(_ policy: String, onCancel: (() -> Void)?) {
        requestAuthorizationForPolicy(policy) { status, error in
            if status == .denied {
                onCancel?()
            }
        }
    }

    @objc public func beginAuthorizationFlow() {
        guard state == "idle" else { return }
        transitionToState("requesting")
        startTimeoutTimer()

        if authorizationStatus == .notDetermined {
            requestInitialAuthorization()
        } else if shouldAttemptAlwaysUpgrade() {
            requestAlwaysUpgrade()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            showSettingsAlert()
        } else {
            completeAuthorizationRequest(authorizationStatus, error: nil)
        }
    }

    @objc public func requestInitialAuthorization() {
        guard let mgr = locationManager else { return }
        DispatchQueue.main.async {
            if self.desiredPolicy == "Always" {
                mgr.requestAlwaysAuthorization()
            } else {
                mgr.requestWhenInUseAuthorization()
            }
        }
    }

    @objc public func requestAlwaysUpgrade() {
        guard let mgr = locationManager else { return }
        DispatchQueue.main.async {
            mgr.requestAlwaysAuthorization()
        }
    }

    @objc public func requestTemporaryFullAccuracy(_ purposeKey: String, completion: ((Error?) -> Void)?) {
        if #available(iOS 14.0, *) {
            locationManager?.requestTemporaryFullAccuracyAuthorization(withPurposeKey: purposeKey) { error in
                completion?(error)
            }
        } else {
            completion?(nil)
        }
    }

    @objc public func requestTemporaryFullAccuracy(_ purposeKey: String, success: (() -> Void)?, failure: ((Error) -> Void)?) {
        requestTemporaryFullAccuracy(purposeKey) { error in
            if let error = error { failure?(error) } else { success?() }
        }
    }

    // MARK: - Alert presentation

    @objc public func showSettingsAlert() {
        dismissCurrentAlert()
        let strings = TSConfig.sharedInstance().getLocationAuthorizationAlertStrings()
        let alert = UIAlertController(
            title: strings["title"] as? String ?? "Background Location Access",
            message: strings["message"] as? String ?? "This app requires location access to operate correctly.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: strings["cancel"] as? String ?? "Cancel", style: .cancel) { [weak self] _ in
            self?.handleAlertCancelled()
        })
        alert.addAction(UIAlertAction(title: strings["settings"] as? String ?? "Settings", style: .default) { [weak self] _ in
            self?.openSettings()
        })
        currentAlert = alert
        presentSettingsAlert()
    }

    @objc public func presentSettingsAlert() {
        guard let alert = currentAlert else { return }
        DispatchQueue.main.async {
            guard let topVC = TSAppState.sharedInstance().topPresenter() else { return }
            topVC.present(alert, animated: true)
        }
    }

    @objc public func dismissCurrentAlert() {
        DispatchQueue.main.async {
            self.currentAlert?.dismiss(animated: false)
            self.currentAlert = nil
        }
    }

    @objc public func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @objc public func hide() {
        dismissCurrentAlert()
    }

    // MARK: - Completion

    @objc public func completeAuthorizationRequest(_ status: CLAuthorizationStatus, error: Error?) {
        cancelTimeoutTimer()
        transitionToState("idle")
        let completions = pendingCompletions
        pendingCompletions.removeAll()
        pendingCompletion = nil
        for c in completions { c(status, error) }
        delegate?.locationAuthorization?(self, didCompleteWith: status, error: error)
    }

    @objc public func cancelAuthorizationRequest() {
        completeAuthorizationRequest(authorizationStatus, error: NSError(domain: "TSLocationAuthorization", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cancelled"]))
    }

    // MARK: - State machine

    @objc public func transitionToState(_ newState: String) {
        state = newState
    }

    @objc public func stateForAuthorizationStatus(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: return "authorized_always"
        case .authorizedWhenInUse: return "authorized_when_in_use"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not_determined"
        @unknown default: return "unknown"
        }
    }

    @objc public func stringForPolicy(_ policy: String) -> String {
        return policy
    }

    @objc public func stringForState(_ state: String) -> String {
        return state
    }

    // MARK: - Timeout

    @objc public func startTimeoutTimer() {
        cancelTimeoutTimer()
        DispatchQueue.main.async {
            self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: self.authorizationTimeoutInterval, repeats: false) { [weak self] _ in
                self?.handleTimeout()
            }
        }
    }

    @objc public func cancelTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    @objc public func handleTimeout() {
        completeAuthorizationRequest(authorizationStatus, error: NSError(domain: "TSLocationAuthorization", code: -2, userInfo: [NSLocalizedDescriptionKey: "Timeout"]))
    }

    // MARK: - Handlers

    @objc public func handleAlertCancelled() {
        completeAuthorizationRequest(authorizationStatus, error: nil)
    }

    @objc public func handleAlwaysGranted() {
        completeAuthorizationRequest(.authorizedAlways, error: nil)
    }

    @objc public func handleWhenInUseGranted() {
        completeAuthorizationRequest(.authorizedWhenInUse, error: nil)
    }

    @objc public func handleAuthorizationDenied() {
        dismissCurrentAlert()
        completeAuthorizationRequest(.denied, error: nil)
    }

    @objc public func onAuthorizationStatusChanged(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        updateAuthorizationState()
        checkAuthorizationStatusForPolicyChange()
        delegate?.locationAuthorization?(self, didChangeAuthorizationStatus: status)
    }

    @objc public func updateAuthorizationState() {
        state = stateForAuthorizationStatus(authorizationStatus)
    }

    @objc public func checkAuthorizationStatusForPolicyChange() {
        guard isRequestInProgress() || state == "requesting" else { return }
        switch authorizationStatus {
        case .authorizedAlways:
            handleAlwaysGranted()
        case .authorizedWhenInUse:
            if desiredPolicy != "Always" { handleWhenInUseGranted() }
        case .denied, .restricted:
            handleAuthorizationDenied()
        default:
            break
        }
    }

    @objc public func onDidBecomeActive() {
        if state == "requesting" && authorizationStatus != .notDetermined {
            checkAuthorizationStatusForPolicyChange()
        }
    }

    @objc public func cleanup() {
        cancelTimeoutTimer()
        dismissCurrentAlert()
    }

    // MARK: - Notifications

    @objc func applicationDidBecomeActive() {
        onDidBecomeActive()
    }

    // MARK: - CLLocationManagerDelegate

    @objc public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        onAuthorizationStatusChanged(status)
    }

    @available(iOS 14.0, *)
    @objc public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        onAuthorizationStatusChanged(status)
        if #available(iOS 14.0, *) {
            let acc = manager.accuracyAuthorization
            accuracyAuthorization = acc == .fullAccuracy ? 1 : 0
        }
    }
}
