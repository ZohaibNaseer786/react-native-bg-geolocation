import Foundation
import CoreLocation

@objc public class TSGeofenceManager: NSObject, CLLocationManagerDelegate {

    private static var _sharedInstance: TSGeofenceManager?
    private static let instanceLock = NSLock()

    @objc public class func sharedInstance() -> TSGeofenceManager {
        instanceLock.lock()
        defer { instanceLock.unlock() }
        if _sharedInstance == nil { _sharedInstance = TSGeofenceManager() }
        return _sharedInstance!
    }

    // MARK: - State

    @objc public var locationManager: CLLocationManager?
    @objc public var enabled: Bool = false
    @objc public var isMoving: Bool = false
    @objc public var count: Int = 0
    @objc public var proximityRadius: CLLocationDistance = 1000
    @objc public var evaluationInterval: TimeInterval = 5.0
    @objc public var bufferInterval: TimeInterval = 0.5
    @objc public var evaluated: Bool = false
    @objc public var lastLocation: CLLocation?
    @objc public var lastEvent: TSGeofenceEvent?
    @objc public var lastAction: String?
    @objc public var lastEvaluatedAt: Date?
    @objc public var didScheduleColdStartReconcile: Bool = false
    @objc public var isMonitoringSignificantLocationChanges: Bool = false
    @objc public var entryStates: [String: String] = [:]
    @objc public var monitoredGeofences: [String: TSGeofence] = [:]
    @objc public var preventSuspendTask: Any?
    @objc public var willEvaluateProximity: Bool = false

    var bufferTimer: Timer?
    var clLocationListener: AnyObject?
    var eventQueue: DispatchQueue?

    private let stateQueue = DispatchQueue(label: "TSGeofenceManager.state", attributes: .concurrent)
    private var clMutationQueue = DispatchQueue(label: "TSGeofenceManager.cl")

    @objc public override init() {
        super.init()
        eventQueue = DispatchQueue(label: "TSGeofenceManager.events")
        registerConfigChangeHandlers()
    }

    @objc public func registerConfigChangeHandlers() {
    }

    // MARK: - Start/Stop

    @objc public func start() {
        guard !enabled else { return }
        enabled = true
        // NOTE: the CLLocationManager delegate is owned solely by TSCLRouter
        // (see TSLocationManager.setupCoreLocation), which forwards region and
        // location callbacks here. Do NOT assign mgr.delegate.
        reconcileMonitoredCacheFromCoreLocation()
    }

    @objc public func stop() {
        guard enabled else { return }
        enabled = false
        stopMonitoringGeofences()
    }

    // MARK: - CL mutation

    @objc public func _mutateCL(_ block: @escaping (CLLocationManager) -> Void) {
        clMutationQueue.async {
            guard let mgr = self.locationManager else { return }
            DispatchQueue.main.async { block(mgr) }
        }
    }

    // MARK: - Geofence management

    @objc public func create(_ geofence: TSGeofence, success: (() -> Void)?, failure: ((Error) -> Void)?) {
        TSGeofenceDAO.sharedInstance().create(geofence)
        startMonitoringGeofence(geofence)
        count = TSGeofenceDAO.sharedInstance().count()
        success?()
    }

    @objc public func destroy(_ identifier: String, success: (() -> Void)?, failure: ((Error) -> Void)?) {
        if let geofence = TSGeofenceDAO.sharedInstance().find(identifier) {
            TSGeofenceDAO.sharedInstance().destroy(identifier)
            stopMonitoringGeofence(geofence)
        }
        count = TSGeofenceDAO.sharedInstance().count()
        success?()
    }

    @objc public func isInfiniteMonitoring() -> Bool {
        return true
    }

    @objc public func startMonitoringGeofence(_ geofence: TSGeofence) {
        _mutateCL { mgr in
            geofence.startMonitoring(withLocationManager: mgr, prefix: "TSGeofence:")
            self.stateQueue.async(flags: .barrier) {
                self.monitoredGeofences[geofence.identifier] = geofence
            }
        }
    }

    @objc public func stopMonitoringGeofence(_ geofence: TSGeofence) {
        _mutateCL { mgr in
            for region in mgr.monitoredRegions {
                if region.identifier.hasSuffix(geofence.identifier) {
                    mgr.stopMonitoring(for: region)
                }
            }
            self.stateQueue.async(flags: .barrier) {
                self.monitoredGeofences.removeValue(forKey: geofence.identifier)
            }
        }
    }

    @objc public func stopMonitoringGeofenceByIdentifier(_ identifier: String) {
        if let geofence = monitoredGeofences[identifier] {
            stopMonitoringGeofence(geofence)
        }
    }

    @objc public func stopMonitoringGeofences() {
        _mutateCL { mgr in
            for region in mgr.monitoredRegions {
                if region.identifier.hasPrefix("TSGeofence:") {
                    mgr.stopMonitoring(for: region)
                }
            }
        }
        stateQueue.async(flags: .barrier) {
            self.monitoredGeofences.removeAll()
        }
    }

    @objc public func isMonitoringRegion(_ identifier: String) -> Bool {
        return monitoredGeofences[identifier] != nil
    }

    @objc public func getMonitoredGeofenceByIdentifier(_ identifier: String) -> TSGeofence? {
        var result: TSGeofence?
        stateQueue.sync { result = monitoredGeofences[identifier] }
        return result
    }

    @objc public func identifierFor(_ region: CLRegion) -> String {
        let id = region.identifier
        if id.hasPrefix("TSGeofence:") {
            return String(id.dropFirst("TSGeofence:".count))
        }
        return id
    }

    @objc public func reconcileMonitoredCacheFromCoreLocation() {
        guard let mgr = locationManager else { return }
        var coreLocationIds = Set<String>()
        for region in mgr.monitoredRegions {
            if region.identifier.hasPrefix("TSGeofence:") {
                coreLocationIds.insert(identifierFor(region))
            }
        }
        let dao = TSGeofenceDAO.sharedInstance()
        let all = dao.all()
        for geofence in all {
            if !coreLocationIds.contains(geofence.identifier) {
                startMonitoringGeofence(geofence)
            }
        }
    }

    // MARK: - Evaluation

    @objc public func setLocation(_ location: CLLocation, isMoving moving: Bool) {
        lastLocation = location
        isMoving = moving
        if moving {
            evaluateProximity(location)
        }
    }

    @objc public func evaluateProximity(_ location: CLLocation) {
        evaluateProximity(location, delay: false)
    }

    @objc public func evaluateProximity(_ location: CLLocation, delay: Bool) {
        guard enabled else { return }
        if delay {
            startBufferTimer()
        } else {
            onEvaluate()
        }
    }

    @objc public func startBufferTimer() {
        bufferTimer?.invalidate()
        DispatchQueue.main.async {
            self.bufferTimer = Timer.scheduledTimer(withTimeInterval: self.bufferInterval, repeats: false) { [weak self] _ in
                self?.onEvaluate()
            }
        }
    }

    @objc public func onEvaluate() {
        guard let location = lastLocation else { return }
        lastEvaluatedAt = Date()
        evaluated = true

        let dao = TSGeofenceDAO.sharedInstance()
        let nearby = dao.allWithinRadius(proximityRadius, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, limit: 20)

        _mutateCL { mgr in
            var needsStartSLC = false
            for geofence in nearby {
                if !self.isMonitoringRegion(geofence.identifier) {
                    geofence.startMonitoring(withLocationManager: mgr, prefix: "TSGeofence:")
                    self.stateQueue.async(flags: .barrier) {
                        self.monitoredGeofences[geofence.identifier] = geofence
                    }
                    needsStartSLC = true
                }
            }
            if needsStartSLC && !self.isMonitoringSignificantLocationChanges {
                self.startMonitoringSignificantLocationChanges()
            }
        }
    }

    // MARK: - Significant location changes

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

    @objc public func onStopMonitoringSLC() {
        stopMonitoringSignificantLocationChanges()
    }

    // MARK: - Event handling

    @objc public func handleGeofenceEvent(_ geofence: TSGeofence, action: String) {
        createEvent(geofence, geofence: geofence, action: action)
    }

    @objc public func createEvent(_ sender: TSGeofence, geofence: TSGeofence, action: String) {
        let identifier = geofence.identifier
        let event = TSGeofenceEvent(identifier: identifier, action: action, timestamp: Date(), geofence: geofence, location: lastLocation, extras: geofence.extras)
        lastEvent = event
        lastAction = action
        geofence.fireEvent(action, location: lastLocation)
        TSGeofenceDAO.sharedInstance().updateState(forIdentifier: identifier, entryState: action == "ENTER" ? "ENTER" : "EXIT", hits: geofence.hits + 1)
        TSEventBus.sharedInstance().emit(TSEventNames.geofence, payload: event.toDictionary())
    }

    // MARK: - CLLocationManagerDelegate

    @objc public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("TSGeofence:") else { return }
        let id = identifierFor(region)
        if let geofence = TSGeofenceDAO.sharedInstance().find(id) {
            if geofence.notifyOnEntry {
                handleGeofenceEvent(geofence, action: "ENTER")
            }
            if geofence.notifyOnDwell && geofence.loiteringDelay > 0 {
                geofence.startLoitering()
            }
        }
    }

    @objc public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier.hasPrefix("TSGeofence:") else { return }
        let id = identifierFor(region)
        if let geofence = TSGeofenceDAO.sharedInstance().find(id) {
            geofence.cancelLoitering()
            if geofence.notifyOnExit {
                handleGeofenceEvent(geofence, action: "EXIT")
            }
        }
    }

    @objc public func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
    }

    @objc public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        TSNativeLogger.error("TSGeofenceManager", message: error.localizedDescription)
    }

    @objc public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        setLocation(location, isMoving: isMoving)
    }

    // MARK: - Info

    @objc public func launchedInBackground() -> Bool {
        return TSAppState.sharedInstance().didLaunchInBackground
    }
}
