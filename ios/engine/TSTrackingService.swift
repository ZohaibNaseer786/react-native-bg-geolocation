import Foundation
import CoreLocation
import UIKit

@objc public class TSTrackingService: NSObject, CLLocationManagerDelegate {

    private static var _sharedInstance: TSTrackingService?
    private static let instanceLock = NSLock()

    @objc public class func sharedInstance() -> TSTrackingService {
        instanceLock.lock()
        defer { instanceLock.unlock() }
        if _sharedInstance == nil { _sharedInstance = TSTrackingService() }
        return _sharedInstance!
    }

    // MARK: - State

    @objc public var locationManager: CLLocationManager?
    @objc public var locationFilter: TSLocationFilter?
    @objc public var locationMetrics: TSLocationMetricsEngine?
    @objc public var beforeInsertBlock: ((TSLocation) -> TSLocation?)?

    @objc public var isEnabled: Bool = false
    @objc public var isMoving: Bool = false
    @objc public var isUpdatingLocation: Bool = false
    @objc public var isMonitoringSignificantLocationChanges: Bool = false
    @objc public var isMonitoringBackgroundFetch: Bool = false
    @objc public var didReceiveFirstLocation: Bool = false
    @objc public var isAwaitingAuthorizationForChangePace: Bool = false

    @objc public var lastLocation: CLLocation?
    @objc public var lastGoodLocation: CLLocation?
    @objc public var lastOdometerLocation: CLLocation?
    @objc public var bestLocation: CLLocation?
    @objc public var stationaryLocation: CLLocation?
    @objc public var prevStationaryLocation: CLLocation?
    @objc public var stationaryRegion: CLCircularRegion?
    @objc public var motionChangeRequest: TSCurrentPositionRequest?
    @objc public var motionStateRequest: TSCurrentPositionRequest?
    @objc public var currentMotionActivity: TSMotionActivity?
    @objc public var locationError: Error?
    @objc public var pendingIsMovingForAuthorization: NSNumber?
    @objc public var preventSuspendTask: Any?

    @objc public var distanceFilter: CLLocationDistance = 10
    @objc public var medianLocationAccuracy: CLLocationAccuracy = 0
    @objc public var lastLocationTimeInterval: TimeInterval = 0
    @objc public var startedAcquiringLocationAt: Date?
    @objc public var stopUpdatingLocationAt: Date?
    @objc public var stoppedAt: Date?
    @objc public var stopOnNextStationary: Bool = false

    private var configChangeBufferTimer: Timer?
    private var startDetectionTimer: Timer?
    private var stopDetectionDelayTimer: Timer?
    private var stopTimeoutTimer: Timer?
    private var motionTriggerTimer: Timer?
    private var locationAccuracyQueue: [CLLocationAccuracy] = []
    private let stateQueue = DispatchQueue(label: "TSTrackingService.state", attributes: .concurrent)
    private let clMutationQueue = DispatchQueue(label: "TSTrackingService.cl")

    @objc public override init() {
        super.init()
        locationFilter = TSLocationFilter()
        locationMetrics = TSLocationMetricsEngine()
    }

    // MARK: - Start / Stop

    @objc public func start(_ isMoving: Bool) {
        guard !isEnabled else { return }
        isEnabled = true
        self.isMoving = isMoving
        didReceiveFirstLocation = false

        registerConfigChangeHandlers()
        registerEventBusHandlers()

        _mutateCL { mgr in
            mgr.delegate = self
            self.applyDistanceFilter(self.distanceFilter)
            self.startUpdatingLocation()
            if isMoving {
                self.beginStartDetection(isMoving)
            }
        }
    }

    @objc public func stop() {
        guard isEnabled else { return }
        isEnabled = false
        stopDetection()
        _mutateCL { mgr in
            self.stopUpdatingLocation()
            self.stopMonitoringStationaryRegion()
        }
    }

    // MARK: - CL mutation

    @objc public func _mutateCL(_ block: @escaping (CLLocationManager) -> Void) {
        clMutationQueue.async {
            guard let mgr = self.locationManager else { return }
            DispatchQueue.main.async { block(mgr) }
        }
    }

    // MARK: - Location updating

    @objc public func startUpdatingLocation() {
        guard !isUpdatingLocation else { return }
        _mutateCL { mgr in
            mgr.startUpdatingLocation()
            self.isUpdatingLocation = true
            self.startedAcquiringLocationAt = Date()
        }
    }

    @objc public func stopUpdatingLocation() {
        guard isUpdatingLocation else { return }
        _mutateCL { mgr in
            mgr.stopUpdatingLocation()
            self.isUpdatingLocation = false
            self.stopUpdatingLocationAt = Date()
        }
    }

    @objc public func startMonitoringSignificantLocationChanges() {
        guard !isMonitoringSignificantLocationChanges else { return }
        _mutateCL { mgr in
            mgr.startMonitoringSignificantLocationChanges()
            self.isMonitoringSignificantLocationChanges = true
        }
    }

    @objc public func stopMonitoringSignificantLocationChanges() {
        guard isMonitoringSignificantLocationChanges else { return }
        _mutateCL { mgr in
            mgr.stopMonitoringSignificantLocationChanges()
            self.isMonitoringSignificantLocationChanges = false
        }
    }

    @objc public func startMonitoringBackgroundFetch() {
        isMonitoringBackgroundFetch = true
    }

    @objc public func stopMonitoringBackgroundFetch() {
        isMonitoringBackgroundFetch = false
    }

    // MARK: - Stationary region

    @objc public func startMonitoringStationaryRegion(_ location: CLLocation, radius: CLLocationDistance) {
        let region = CLCircularRegion(center: location.coordinate, radius: radius, identifier: "TSStationary")
        region.notifyOnExit = true
        stationaryRegion = region
        _mutateCL { mgr in
            mgr.startMonitoring(for: region)
        }
    }

    func stopMonitoringStationaryRegion() {
        if let region = stationaryRegion {
            _mutateCL { mgr in
                mgr.stopMonitoring(for: region)
            }
            stationaryRegion = nil
        }
    }

    @objc public func stationaryRegionContains(location: CLLocation) -> Bool {
        guard let region = stationaryRegion else { return false }
        return region.contains(location.coordinate)
    }

    @objc public func locationIsBeyondStationaryRegion(_ location: CLLocation) -> Bool {
        guard let region = stationaryRegion else { return true }
        return !region.contains(location.coordinate)
    }

    // MARK: - Pace change

    @objc public func changePace(_ moving: Bool) {
        if isEnabled {
            setMoving(moving)
        } else {
            pendingIsMovingForAuthorization = NSNumber(value: moving)
        }
    }

    private func setMoving(_ moving: Bool) {
        let wasMoving = isMoving
        isMoving = moving

        if moving && !wasMoving {
            beginStartDetection(moving)
        } else if !moving && wasMoving {
            beginStopDetection()
        }
    }

    // MARK: - Start detection

    @objc public func beginStartDetection() {
        beginStartDetection(true)
    }

    @objc public func beginStartDetection(_ moving: Bool) {
        endStopDetection()
        stopMonitoringStationaryRegion()
        startUpdatingLocation()
        startMotionTriggerTimer()
    }

    @objc public func endStartDetection() {
        startDetectionTimer?.invalidate()
        startDetectionTimer = nil
    }

    @objc public func detectStartMotion(_ location: CLLocation) {
        guard !isMoving else { return }
        isMoving = true
        onMotionChangeSuccess(true, location: location, didPersist: false)
    }

    // MARK: - Stop detection

    @objc public func beginStopDetection() {
        stopDetectionDelayTimer?.invalidate()
        let config = TSConfig.sharedInstance()
        let stopTimeout = config.geolocation.stopTimeout * 60

        stopDetectionDelayTimer = Timer.scheduledTimer(withTimeInterval: stopTimeout, repeats: false) { [weak self] _ in
            self?.detectStopMotion(nil)
        }
    }

    @objc public func endStopDetection() {
        stopDetectionDelayTimer?.invalidate()
        stopDetectionDelayTimer = nil
        stopTimeoutTimer?.invalidate()
        stopTimeoutTimer = nil
    }

    func stopDetection() {
        endStartDetection()
        endStopDetection()
        stopMotionTriggerTimer()
    }

    @objc public func beginStopDetectionDelayTimer() {
        beginStopDetection()
    }

    @objc public func detectStopMotion(_ location: CLLocation?) {
        guard isMoving else { return }
        isMoving = false
        let loc = location ?? lastGoodLocation
        onMotionChangeSuccess(false, location: loc, didPersist: false)
    }

    @objc public func onStopTimeout() {
        detectStopMotion(lastGoodLocation)
    }

    @objc public func resetStopDetectionDelayTimer() {
        stopDetectionDelayTimer?.invalidate()
        beginStopDetection()
    }

    @objc public func resetStopTimeoutTimer() {
        stopTimeoutTimer?.invalidate()
    }

    // MARK: - Motion trigger timer

    @objc public func startMotionTriggerTimer() {
        motionTriggerTimer?.invalidate()
        let interval: TimeInterval = 30.0
        DispatchQueue.main.async {
            self.motionTriggerTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                self?.onMotionTrigger()
            }
        }
    }

    @objc public func stopMotionTriggerTimer() {
        motionTriggerTimer?.invalidate()
        motionTriggerTimer = nil
    }

    @objc public func resetMotionTriggerTimer() {
        stopMotionTriggerTimer()
        startMotionTriggerTimer()
    }

    @objc public func onMotionTrigger() {
        guard isEnabled else { return }
        if let best = bestLocation {
            detectStartMotion(best)
        }
    }

    // MARK: - Heartbeat

    @objc public func beginHeartbeat() {
        let config = TSConfig.sharedInstance()
        let interval = config.app.heartbeatInterval
        TSHeartbeatService.sharedInstance().startWithInterval(interval) { [weak self] _ in
            self?.onHeartbeat()
        }
    }

    @objc public func stopHeartbeat() {
        TSHeartbeatService.sharedInstance().stop()
    }

    @objc public func onHeartbeat() {
        TSEventBus.sharedInstance().emit(TSEventNames.heartbeat, payload: ["location": lastLocation.map { ["timestamp": $0.timestamp.timeIntervalSince1970] } ?? [:]])
    }

    @objc public func evaluateHeartbeatTimer() {
        let config = TSConfig.sharedInstance()
        if config.app.heartbeatInterval > 0 && isEnabled {
            beginHeartbeat()
        } else {
            stopHeartbeat()
        }
    }

    // MARK: - Location processing

    @objc public func locationIsGoodEnough(_ location: CLLocation) -> Bool {
        let config = TSConfig.sharedInstance()
        let desiredAccuracy = config.geolocation.desiredAccuracy
        return location.horizontalAccuracy <= desiredAccuracy || desiredAccuracy == 0
    }

    @objc public func calculateDistanceFilter(_ location: CLLocation) -> CLLocationDistance {
        let config = TSConfig.sharedInstance()
        let base = config.geolocation.distanceFilter
        if config.geolocation.disableElasticity { return base }
        let speed = max(0, location.speed)
        let multiplier = config.geolocation.elasticityMultiplier
        let elastic = base + speed * multiplier
        return elastic
    }

    @objc public func calculateMedianLocationAccuracy(_ accuracies: [CLLocationAccuracy]) -> CLLocationAccuracy {
        guard !accuracies.isEmpty else { return 0 }
        let sorted = accuracies.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    @objc public func applyDistanceFilter(_ filter: CLLocationDistance) {
        distanceFilter = filter
        _mutateCL { mgr in mgr.distanceFilter = filter }
    }

    @objc public func persistLocation(_ location: TSLocation) {
        if let block = beforeInsertBlock {
            guard let modified = block(location) else { return }
            _ = TSLocationDAO.sharedInstance().create(modified, error: nil)
        } else {
            _ = TSLocationDAO.sharedInstance().create(location, error: nil)
        }
    }

    @objc public func persistStationaryLocation(_ location: CLLocation) {
        let tsLocation = TSLocation(location: location, type: "stationary", extras: nil)
        _ = TSLocationDAO.sharedInstance().create(tsLocation, error: nil)
        stationaryLocation = location
        UserDefaults.standard.set(try? JSONSerialization.data(withJSONObject: tsLocation.toDictionary()), forKey: "TSLocationManager_stationary")
    }

    @objc public func loadStationaryLocation() {
        if let data = UserDefaults.standard.data(forKey: "TSLocationManager_stationary"),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            stationaryLocation = TSLocationDAO.sharedInstance().inflate(dict).location
        }
    }

    @objc public func destroyStationaryLocation() {
        UserDefaults.standard.removeObject(forKey: "TSLocationManager_stationary")
        stationaryLocation = nil
    }

    // MARK: - Motion change

    @objc public func onMotionChangeSuccess(_ moving: Bool, location: CLLocation?, didPersist: Bool) {
        let loc = location ?? lastGoodLocation
        let tsLocation = loc.map { TSLocation(location: $0, type: "motionchange", extras: nil) }
        tsLocation?.isMoving = moving

        if let tsLoc = tsLocation, !didPersist {
            persistLocation(tsLoc)
        }

        // Deliver TSLocation object to RN module listeners (onMotionChange: registered via TSEventManager)
        if let tsLoc = tsLocation {
            TSEventManager.sharedInstance().trigger(TSEventNames.motionChangeComplete, payload: tsLoc)
        }
        // Keep TSEventBus emission for internal engine consumers
        TSEventBus.sharedInstance().emit(TSEventNames.motionChangeComplete, payload: [
            "isMoving": moving,
            "location": tsLocation?.toDictionary() ?? [:]
        ])

        if moving {
            stopMonitoringStationaryRegion()
            beginHeartbeat()
        } else {
            stopHeartbeat()
            if let loc = loc {
                let config = TSConfig.sharedInstance()
                startMonitoringStationaryRegion(loc, radius: config.geolocation.stationaryRadius)
            }
        }
    }

    @objc public func onMotionChangeError(_ error: Error) {
        locationError = error
        TSEventBus.sharedInstance().emit(TSEventNames.motionChangeError, payload: ["error": error.localizedDescription])
    }

    // MARK: - Current position

    @objc public func getCurrentPosition(_ request: TSCurrentPositionRequest) {
        TSLocationRequestService.sharedInstance().requestLocation(request)
    }

    // MARK: - Location error event

    @objc public func fireLocationErrorEvent(_ error: Error) {
        TSEventBus.sharedInstance().emit(TSEventNames.locationError, payload: ["error": error.localizedDescription])
    }

    // MARK: - Odometer

    @objc public func setOdometer(_ value: Double, request: TSCurrentPositionRequest?) {
        TSOdometer.sharedInstance().setOdometer(value, location: lastGoodLocation)
        lastOdometerLocation = lastGoodLocation
    }

    // MARK: - Schedule

    @objc public func startSchedule() {
        _ = TSScheduler.sharedInstance().start(withSchedule: TSConfig.sharedInstance().app.schedule)
    }

    @objc public func startGeofences() {
        TSGeofenceManager.sharedInstance().start()
    }

    // MARK: - Significant location monitoring

    @objc public func onStopMonitoringSLC() {
        stopMonitoringSignificantLocationChanges()
    }

    // MARK: - Config change handlers

    @objc public func registerConfigChangeHandlers() {
    }

    @objc public func registerEventBusHandlers() {
    }

    @objc public func onChangeDesiredAccuracy(_ accuracy: CLLocationAccuracy) {
        _mutateCL { mgr in mgr.desiredAccuracy = accuracy }
    }

    @objc public func onChangeDistanceFilter(_ filter: CLLocationDistance) {
        applyDistanceFilter(filter)
    }

    @objc public func onChangeActivityType(_ type: String) {
        let activityType = TSGeolocationConfig.activityType(fromString: type)
        _mutateCL { mgr in mgr.activityType = activityType }
    }

    @objc public func onChangePausesLocationUpdatesAutomatically(_ pauses: Bool) {
        _mutateCL { mgr in mgr.pausesLocationUpdatesAutomatically = pauses }
    }

    @objc public func onChangeShowsBackgroundLocationIndicator(_ shows: Bool) {
        if #available(iOS 11.0, *) {
            _mutateCL { mgr in mgr.showsBackgroundLocationIndicator = shows }
        }
    }

    @objc public func onChangeUseSignificantChangesOnly(_ enabled: Bool) {
        if enabled {
            stopUpdatingLocation()
            startMonitoringSignificantLocationChanges()
        } else {
            stopMonitoringSignificantLocationChanges()
            startUpdatingLocation()
        }
    }

    @objc public func onChangeLocationAuthorizationRequest(_ request: String) {
    }

    @objc public func onChangeHeartbeatInterval(_ interval: TimeInterval) {
        evaluateHeartbeatTimer()
    }

    @objc public func onChangeActivityRecognitionInterval(_ interval: TimeInterval) {
    }

    @objc public func onChangeDisableMotionActivityUpdates(_ disabled: Bool) {
    }

    @objc public func onChangeElasticity(_ enabled: Bool) {
    }

    @objc public func onChangePreventSuspend(_ enabled: Bool) {
    }

    @objc public func onChangeScheduleEvent(_ event: TSScheduleEvent) {
    }

    // MARK: - Event handlers

    @objc public func onScheduleEvent(_ event: TSScheduleEvent) {
    }

    @objc public func onMotionActivityChange(_ activity: TSMotionActivity) {
        currentMotionActivity = activity
        let moving = activity.type != "still"
        if moving != isMoving {
            setMoving(moving)
        }
    }

    @objc public func onLocationError(_ error: Error) {
        locationError = error
        fireLocationErrorEvent(error)
    }

    @objc public func onResume() {
        if isEnabled { startUpdatingLocation() }
    }

    @objc public func onSuspend() {
        if isEnabled && !isMoving {
            stopUpdatingLocation()
            startMonitoringSignificantLocationChanges()
        }
    }

    @objc public func onAppTerminate() {
        stop()
    }

    @objc public func updateCurrentState() {
    }

    @objc public func onUpdateState(_ state: [String: Any]) {
    }

    @objc public func shouldStopAfterElapsedMinutes() -> Bool {
        return false
    }

    @objc public func stopAfterElapsedMinutes() -> TimeInterval {
        return 0
    }

    @objc public func isInBackground() -> Bool {
        return TSAppState.sharedInstance().isInBackground
    }

    // MARK: - CLLocationManagerDelegate

    @objc public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        let config = TSConfig.sharedInstance()

        locationAccuracyQueue.append(location.horizontalAccuracy)
        if locationAccuracyQueue.count > 10 { locationAccuracyQueue.removeFirst() }
        medianLocationAccuracy = calculateMedianLocationAccuracy(locationAccuracyQueue)

        lastLocation = location

        if locationIsGoodEnough(location) {
            lastGoodLocation = location
            if !didReceiveFirstLocation {
                didReceiveFirstLocation = true
            }
            bestLocation = location
        }

        let newDistanceFilter = calculateDistanceFilter(location)
        if newDistanceFilter != distanceFilter {
            applyDistanceFilter(newDistanceFilter)
        }

        TSGeofenceManager.sharedInstance().setLocation(location, isMoving: isMoving)

        let tsLocation = TSLocation(location: location, type: isMoving ? "tracking" : "stationary", extras: nil)
        tsLocation.isMoving = isMoving
        tsLocation.odometer = TSOdometer.sharedInstance().getOdometer()

        if config.shouldPersist(tsLocation) {
            persistLocation(tsLocation)
        }

        // Deliver to RN module listeners (BgGeolocation.mm registered via onLocation:)
        TSEventManager.sharedInstance().triggerLocationSuccess(tsLocation)
        // Keep TSEventBus emission for any internal engine consumers
        TSEventBus.sharedInstance().emit(TSEventNames.locationComplete, payload: tsLocation.toDictionary())
    }

    @objc public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        TSEventManager.sharedInstance().triggerLocationError(error)
        onLocationError(error)
    }

    @objc public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        TSLocationAuthorization.sharedInstance().onAuthorizationStatusChanged(status)
    }

    @objc public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == "TSStationary" else { return }
        if !isMoving {
            detectStartMotion(lastLocation ?? CLLocation())
        }
    }

    @objc public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
    }

    @objc public func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        isUpdatingLocation = false
    }

    @objc public func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        isUpdatingLocation = true
    }

    // MARK: - KVO

    @objc public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    }
}
