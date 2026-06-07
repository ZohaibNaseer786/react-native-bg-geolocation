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
    private var motionObserver: NSObjectProtocol?
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
        loadStationaryLocation()

        registerConfigChangeHandlers()
        registerEventBusHandlers()

        _mutateCL { mgr in
            // NOTE: the delegate is owned solely by TSCLRouter (see
            // TSLocationManager.setupCoreLocation). Do NOT assign it here.
            self.configureLocationManager(mgr)
            self.startMonitoringSignificantLocationChanges()
            if let stationary = self.stationaryLocation, !isMoving {
                self.startMonitoringStationaryRegion(stationary, radius: TSConfig.sharedInstance().geolocation.stationaryRadius)
            }
            if TSConfig.sharedInstance().geolocation.useSignificantChangesOnly {
                self.stopUpdatingLocation()
            } else {
                self.startUpdatingLocation()
            }
            if isMoving {
                self.beginStartDetection(isMoving)
            }
        }
        startMotionMonitoring()
        evaluateHeartbeatTimer()
    }

    @objc public func stop() {
        guard isEnabled else { return }
        isEnabled = false
        stopDetection()
        stopMotionMonitoring()
        _mutateCL { mgr in
            self.stopUpdatingLocation()
            self.stopMonitoringSignificantLocationChanges()
            self.stopMonitoringStationaryRegion()
        }
        stopHeartbeat()
    }

    // MARK: - Motion activity monitoring
    //
    // Drives autonomous stationary<->moving transitions from CMMotionActivity
    // (the motion coprocessor). Previously TSMotionDetector was never started
    // and its updates were observed by nobody, so the only way to detect motion
    // onset was a coarse stationary-region exit. Now the detector runs while
    // tracking is enabled and feeds onMotionActivityChange -> changePace.

    @objc public func startMotionMonitoring() {
        let detector = TSMotionDetector.sharedInstance()
        detector.start()
        if motionObserver == nil {
            motionObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("TSMotionDetectorDidUpdateActivity"),
                object: nil, queue: .main
            ) { [weak self] note in
                if let activity = note.object as? TSMotionActivity {
                    self?.onMotionActivityChange(activity)
                }
            }
        }
    }

    @objc public func stopMotionMonitoring() {
        TSMotionDetector.sharedInstance().stop()
        if let obs = motionObserver {
            NotificationCenter.default.removeObserver(obs)
            motionObserver = nil
        }
    }

    // MARK: - CL mutation

    @objc public func _mutateCL(_ block: @escaping (CLLocationManager) -> Void) {
        clMutationQueue.async {
            guard let mgr = self.locationManager else { return }
            DispatchQueue.main.async { block(mgr) }
        }
    }

    @objc public func configureLocationManager(_ manager: CLLocationManager) {
        let config = TSConfig.sharedInstance().geolocation
        manager.desiredAccuracy = config.desiredAccuracy
        manager.distanceFilter = config.distanceFilter
        manager.activityType = config.activityType
        manager.pausesLocationUpdatesAutomatically = config.pausesLocationUpdatesAutomatically
        if #available(iOS 9.0, *) {
            manager.allowsBackgroundLocationUpdates = TSAppState.sharedInstance().hasBackgroundLocationMode()
        }
        if #available(iOS 11.0, *) {
            manager.showsBackgroundLocationIndicator = config.showsBackgroundLocationIndicator
        }
        distanceFilter = config.distanceFilter
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

    /// Re-assert tracking's intended continuous-updates state on the shared
    /// CLLocationManager. Called by TSLocationRequestService after a
    /// getCurrentPosition fix completes, so a one-off fix powering up GPS does
    /// not leave it running (or off) against tracking's wishes.
    @objc public func restoreUpdatingState() {
        guard isEnabled else { return }
        let geo = TSConfig.sharedInstance().geolocation
        _mutateCL { mgr in
            if geo.disableStopDetection || (self.isMoving && !geo.useSignificantChangesOnly) {
                mgr.startUpdatingLocation()
                self.isUpdatingLocation = true
            } else {
                mgr.stopUpdatingLocation()
                self.isUpdatingLocation = false
            }
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
        // iOS CLCircularRegion monitoring is cell/wifi-coarse and unreliable
        // below ~100-150m: a small radius either never fires the real exit or
        // fires spurious exits from GPS jitter. The stationary region is the
        // primary mechanism that wakes a suspended or system-terminated app when the user
        // departs, so clamp it to a dependable minimum (decoupled from the
        // motion stop/start `stationaryRadius` distance logic).
        let minReliableRadius: CLLocationDistance = 200.0
        let effectiveRadius = max(radius, minReliableRadius)
        let region = CLCircularRegion(center: location.coordinate, radius: effectiveRadius, identifier: "TSStationary")
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
        // Continuous keep-alive ("ride app") mode: never relinquish the moving
        // state, so GPS stays on and the app stays alive in the background with
        // the location indicator. Ignore stationary transitions entirely.
        if !moving && TSConfig.sharedInstance().geolocation.disableStopDetection {
            return
        }
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
        // Renew the keep-alive background task so the next interval can fire
        // while briefly suspended (best-effort; true kill-state longevity comes
        // from SLC/region wake, not from background tasks).
        if TSConfig.sharedInstance().app.preventSuspend {
            TSBackgroundTaskManager.sharedInstance().renewPreventSuspend()
        }
        // Emit the typed event the bridge/listener expects (a TSHeartbeatEvent,
        // not a raw dictionary — the previous payload type never matched and so
        // never reached JS onHeartbeat).
        let event = TSHeartbeatEvent(location: lastLocation ?? lastGoodLocation)
        TSEventBus.sharedInstance().emit(TSEventNames.heartbeat, payload: event)
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
        var didPersist = false
        if let block = beforeInsertBlock {
            guard let modified = block(location) else { return }
            didPersist = TSLocationDAO.sharedInstance().create(modified, error: nil)
        } else {
            didPersist = TSLocationDAO.sharedInstance().create(location, error: nil)
        }

        let httpConfig = TSConfig.sharedInstance().http
        if didPersist && httpConfig.autoSync && httpConfig.hasValidUrl {
            let http = TSHttpService.sharedInstance()
            if isInBackground() || TSAppState.sharedInstance().didLaunchInBackground {
                http.flushForBackgroundWake()
            } else {
                http.flush()
            }
        }
    }

    @objc public func persistStationaryLocation(_ location: CLLocation) {
        let tsLocation = TSLocation(location: location, type: "stationary", extras: nil)
        _ = TSLocationDAO.sharedInstance().create(tsLocation, error: nil)
        stationaryLocation = location
        UserDefaults.standard.set(try? JSONSerialization.data(withJSONObject: tsLocation.toDictionary()), forKey: "TSLocationManager_stationary")
        if TSConfig.sharedInstance().http.autoSync && TSConfig.sharedInstance().http.hasValidUrl {
            let http = TSHttpService.sharedInstance()
            if isInBackground() || TSAppState.sharedInstance().didLaunchInBackground {
                http.flushForBackgroundWake()
            } else {
                http.flush()
            }
        }
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
            startMonitoringSignificantLocationChanges()
            startUpdatingLocation()
        } else {
            // Going stationary: persist the stop, arm the wake mechanisms (SLC +
            // stationary region), and CRITICALLY tear down the high-power
            // continuous GPS stream — otherwise full-accuracy GPS runs forever
            // while parked (the biggest iOS battery drain, and the exact thing
            // the stationary state exists to prevent).
            if let loc = loc {
                let config = TSConfig.sharedInstance()
                persistStationaryLocation(loc)
                startMonitoringStationaryRegion(loc, radius: config.geolocation.stationaryRadius)
            }
            startMonitoringSignificantLocationChanges()
            // Keep GPS running in continuous keep-alive mode; otherwise tear it
            // down to save battery and rely on SLC/region wakeups.
            if !TSConfig.sharedInstance().geolocation.disableStopDetection {
                stopUpdatingLocation()
            }
        }
        // Heartbeat lifecycle is owned by evaluateHeartbeatTimer() for the whole
        // enabled session, so it keeps firing across pace changes (including
        // while stationary, which is when it matters most).
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
        // Surface the activitychange event to JS (nothing emitted this before,
        // so BackgroundGeolocation.onActivityChange never fired).
        TSEventBus.sharedInstance().emit(TSEventNames.activityChange, payload: activity)
        // Drive pace from the detected activity. "still"/"unknown" => stationary;
        // anything else (walking/running/in_vehicle/on_bicycle) => moving. Route
        // through changePace so the pending-authorization path is honored.
        let moving = activity.type != "still" && activity.type != "unknown"
        TSLiveActivityManager.shared.update(
            location: lastGoodLocation,
            isMoving: moving,
            activity: activity.type,
            force: true
        )
        if moving != isMoving {
            changePace(moving)
        }
    }

    @objc public func onLocationError(_ error: Error) {
        locationError = error
        fireLocationErrorEvent(error)
    }

    @objc public func onResume() {
        if isEnabled {
            startMonitoringSignificantLocationChanges()
            if !TSConfig.sharedInstance().geolocation.useSignificantChangesOnly {
                startUpdatingLocation()
            }
        }
    }

    @objc public func onSuspend() {
        guard isEnabled else { return }
        let geo = TSConfig.sharedInstance().geolocation
        startMonitoringSignificantLocationChanges()
        // Continuous keep-alive mode: keep GPS running while backgrounded so the
        // app is never suspended (this is what shows the status-bar indicator and
        // is how ride apps stay alive). Otherwise downgrade to SLC + stationary
        // region to save battery.
        if geo.disableStopDetection || (isMoving && !geo.useSignificantChangesOnly) {
            startUpdatingLocation()
        } else {
            startMonitoringSignificantLocationChanges()
            if let loc = stationaryLocation ?? lastGoodLocation {
                startMonitoringStationaryRegion(loc, radius: geo.stationaryRadius)
            }
            stopUpdatingLocation()
        }
    }

    @objc public func onAppTerminate() {
        let config = TSConfig.sharedInstance()
        guard config.app.stopOnTerminate else {
            config.enabled = true
            config.isMoving = isMoving
            config.forcePersistNow()
            // UIApplication.willTerminate handlers MUST work synchronously — iOS
            // kills the process shortly after this returns, so the async
            // _mutateCL (clMutationQueue -> main) hop used elsewhere would be
            // dropped. Re-arm the wake mechanisms directly on the manager here.
            // (We are already on the main thread for this notification.)
            if let mgr = locationManager {
                configureLocationManager(mgr)
                mgr.startMonitoringSignificantLocationChanges()
                isMonitoringSignificantLocationChanges = true
                if let loc = stationaryLocation ?? lastGoodLocation {
                    let radius = max(config.geolocation.stationaryRadius, 200.0)
                    let region = CLCircularRegion(center: loc.coordinate, radius: radius, identifier: "TSStationary")
                    region.notifyOnExit = true
                    stationaryRegion = region
                    mgr.startMonitoring(for: region)
                }
            }
            return
        }
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

        NSLog("[BGGEO] didUpdateLocations: lat=\(location.coordinate.latitude) lng=\(location.coordinate.longitude) acc=\(location.horizontalAccuracy) background=\(isInBackground()) moving=\(isMoving)")

        let config = TSConfig.sharedInstance()

        locationAccuracyQueue.append(location.horizontalAccuracy)
        if locationAccuracyQueue.count > 10 { locationAccuracyQueue.removeFirst() }
        medianLocationAccuracy = calculateMedianLocationAccuracy(locationAccuracyQueue)

        lastLocation = location

        if locationIsGoodEnough(location) {
            lastGoodLocation = location
            if !didReceiveFirstLocation {
                didReceiveFirstLocation = true
                if !isMoving {
                    persistStationaryLocation(location)
                    startMonitoringStationaryRegion(location, radius: config.geolocation.stationaryRadius)
                }
            }
            bestLocation = location
        }

        let newDistanceFilter = calculateDistanceFilter(location)
        if newDistanceFilter != distanceFilter {
            applyDistanceFilter(newDistanceFilter)
        }

        TSGeofenceManager.sharedInstance().setLocation(location, isMoving: isMoving)
        // Give the motion classifier speed/location context so its
        // walking/running/vehicle classification can use speed alongside the
        // accelerometer / CMMotionActivity signal.
        TSMotionDetector.sharedInstance().setLocation(location, isMoving: isMoving)

        // Speed-based motion onset. CMMotionActivity is unreliable for vehicles
        // and bikes — when the phone is held steady the classifier reports
        // `unknown`/`stationary` even at speed, which kept isMoving=false on real
        // rides. GPS speed is decisive here, so flip to moving when we see real
        // ground speed regardless of the activity classifier. (Going back to
        // stationary is still handled by stop-detection / activity, except in
        // keep-alive mode where we intentionally never stop.)
        let speedMovingThreshold: CLLocationDistance = 1.5 // m/s ≈ 5.4 km/h
        if location.speed >= 0, location.speed > speedMovingThreshold, !isMoving {
            NSLog("[BGGEO] speed-based motion onset: speed=\(location.speed) m/s -> moving")
            detectStartMotion(location)
        }

        let tsLocation = TSLocation(location: location, type: isMoving ? "tracking" : "stationary", extras: nil)
        tsLocation.isMoving = isMoving
        tsLocation.odometer = TSOdometer.sharedInstance().getOdometer()

        if config.shouldPersist(tsLocation) {
            persistLocation(tsLocation)
        }

        TSLiveActivityManager.shared.update(
            location: location,
            isMoving: isMoving,
            activity: currentMotionActivity?.type ?? (isMoving ? "moving" : "still"),
            force: false
        )

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
            startUpdatingLocation()
            let fallback: CLLocation
            if let circular = region as? CLCircularRegion {
                fallback = CLLocation(latitude: circular.center.latitude, longitude: circular.center.longitude)
            } else {
                fallback = CLLocation()
            }
            detectStartMotion(lastLocation ?? lastGoodLocation ?? fallback)
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
