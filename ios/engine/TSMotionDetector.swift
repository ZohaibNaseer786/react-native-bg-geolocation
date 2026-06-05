import Foundation
import CoreMotion
import CoreLocation

@objc public class TSMotionDetector: NSObject, TSMotionActivitySourceDelegate {

    private static var _sharedInstance: TSMotionDetector?
    private static let instanceLock = NSLock()

    @objc public class func sharedInstance() -> TSMotionDetector {
        instanceLock.lock()
        defer { instanceLock.unlock() }
        if _sharedInstance == nil { _sharedInstance = TSMotionDetector() }
        return _sharedInstance!
    }

    public class func motionAuthorizationStatus() -> CMAuthorizationStatus {
        return CMMotionActivityManager.authorizationStatus()
    }

    @objc public class func motionHardwareAvailable() -> Bool {
        return CMMotionActivityManager.isActivityAvailable()
    }

    // MARK: - State

    @objc public var enabled: Bool = false
    @objc public var debug: Bool = false
    @objc public var isMoving: Bool = false
    @objc public var isUpdatingMotionActivity: Bool = false
    @objc public var useM7IfAvailable: Bool = true
    @objc public var useAccelerometerFallback: Bool = true
    @objc public var autoRequestMotionPermission: Bool = true

    // Activity state
    @objc public var motionType: String = "unknown"
    @objc public var previousMotionType: String = "unknown"
    @objc public var statedActivity: TSMotionActivity?
    @objc public var currentActivity: TSMotionActivity?
    @objc public var motionActivity: CMMotionActivity?
    @objc public var detectorState: String = "stopped"
    @objc public var history: [TSMotionActivity] = []
    @objc public var diagnostics: [String: Any] = [:]

    // Speed/location state
    @objc public var location: CLLocation?
    @objc public var currentSpeed: Double = 0

    // Confidence tracking
    @objc public var lastConfidence: Int = 0
    @objc public var lastEmittedType: String = "unknown"
    @objc public var lastEmittedConfidence: Int = 0
    @objc public var lastTypeChangeAt: Date?
    @objc public var confidenceDeltaThreshold: Int = 1
    @objc public var minimumMotionActivityConfidence: Int = 1

    // Sensor state
    public var acceleration: CMAcceleration = CMAcceleration()
    @objc public var accelerometerUpdateInterval: TimeInterval = 0.1
    @objc public var samplesPerInterval: Int = 50
    @objc public var detectMotionWindow: TimeInterval = 5.0

    // M7 detection thresholds
    @objc public var isUsingM7: Bool = false
    @objc public var M7Authorized: Bool = false

    // Motion probe settings (adaptive polling)
    @objc public var probeMinInterval: TimeInterval = 5.0
    @objc public var probeCooldownBase: TimeInterval = 15.0
    @objc public var probeCooldownMax: TimeInterval = 120.0
    @objc public var probeFreshSpeedAge: TimeInterval = 10.0
    @objc public var probeFreshSpeedThreshold: Double = 0.5
    @objc public var probeHighConfidence: Int = 75
    @objc public var probeDwellWins: Int = 3

    // Stop detection
    @objc public var stopDwellWins: Int = 3
    @objc public var stopHighConfidence: Int = 90
    @objc public var sdConsecutiveStillWins: Int = 0
    @objc public var mdConsecutiveMovingWins: Int = 0
    @objc public var mdBackoffLevel: Int = 0
    @objc public var mdLastProbeAt: Date?
    @objc public var mdLastSpeedAt: Date?
    @objc public var mdLastSpeedValue: Double = 0
    @objc public var mdSuppressUntil: Date?

    // Type debounce
    @objc public var motionDebounceInterval: TimeInterval = 1.0
    @objc public var typeDebounceInterval: TimeInterval = 2.0
    @objc public var motionDetectionInterval: TimeInterval = 10.0

    // Speed thresholds
    @objc public var minimumSpeed: Double = 0.5
    @objc public var maximumWalkingSpeed: Double = 3.0
    @objc public var maximumRunningSpeed: Double = 10.0

    // Sensors
    @objc public var motionManager: CMMotionManager?
    @objc public var motionActivityManager: CMMotionActivityManager?
    @objc public var activitySource: TSMotionActivitySource?
    @objc public var activityClassifier: TSMotionActivityClassifier?
    @objc public var permissionMgr: TSMotionPermissionManager?
    @objc public var activityProvider: AnyObject?

    var accelerometerQueue: OperationQueue?
    var windowTimer: Timer?
    var stateQueue: DispatchQueue?

    @objc public var accelerationChangedBlock: ((CMAccelerometerData) -> Void)?
    @objc public var motionActivityChangedBlock: ((CMMotionActivity) -> Void)?

    @objc public override init() {
        super.init()
        stateQueue = DispatchQueue(label: "TSMotionDetector.state")
        activityClassifier = TSMotionActivityClassifier()
        activityClassifier?.configureWithSampleInterval(0.1, windowSeconds: 5.0)
        permissionMgr = TSMotionPermissionManager()
    }

    // MARK: - Authorization

    @objc public func isAccelerometerAvailable() -> Bool {
        return motionManager?.isAccelerometerAvailable ?? false
    }

    @objc public func isGyroAvailable() -> Bool {
        return motionManager?.isGyroAvailable ?? false
    }

    @objc public func isDeviceMotionAvailable() -> Bool {
        return motionManager?.isDeviceMotionAvailable ?? false
    }

    @objc public func isMagnetometerAvailable() -> Bool {
        return motionManager?.isMagnetometerAvailable ?? false
    }

    @objc public func isConfidentlyStationary() -> Bool {
        guard motionType == "still" else { return false }
        return sdConsecutiveStillWins >= stopDwellWins
    }

    // MARK: - Lifecycle

    @objc public func start() {
        guard !enabled else { return }
        enabled = true
        detectorState = "running"

        motionManager = CMMotionManager()
        motionManager?.accelerometerUpdateInterval = accelerometerUpdateInterval

        if useM7IfAvailable && TSMotionDetector.motionHardwareAvailable() {
            startM7Detection()
        } else if useAccelerometerFallback {
            startSensorDetection()
        }
    }

    @objc public func stop() {
        guard enabled else { return }
        enabled = false
        detectorState = "stopped"
        stopSensorDetection()
        activitySource?.stop()
        windowTimer?.invalidate()
        windowTimer = nil
    }

    @objc public func startSensorDetection() {
        guard let mgr = motionManager, mgr.isAccelerometerAvailable else { return }
        accelerometerQueue = OperationQueue()
        accelerometerQueue?.name = "TSMotionDetector.accelerometer"
        mgr.startAccelerometerUpdates(to: accelerometerQueue!) { [weak self] data, error in
            guard let self = self, let data = data else { return }
            self.activityClassifier?.ingestAcceleration(data)
            self.accelerationChangedBlock?(data)
        }

        if mgr.isGyroAvailable {
            mgr.startGyroUpdates(to: accelerometerQueue!) { [weak self] data, error in
                guard let self = self, let data = data else { return }
                self.activityClassifier?.ingestRotationRate(data)
            }
        }

        scheduleWindowTimer()
    }

    @objc public func stopSensorDetection() {
        motionManager?.stopAccelerometerUpdates()
        motionManager?.stopGyroUpdates()
        accelerometerQueue?.cancelAllOperations()
        accelerometerQueue = nil
        windowTimer?.invalidate()
        windowTimer = nil
    }

    private func startM7Detection() {
        isUsingM7 = true
        let queue = DispatchQueue(label: "TSMotionDetector.M7")
        activitySource = TSMotionActivitySource()
        activitySource?.delegate = self
        activitySource?.start()
    }

    private func scheduleWindowTimer() {
        DispatchQueue.main.async {
            self.windowTimer?.invalidate()
            self.windowTimer = Timer.scheduledTimer(withTimeInterval: self.detectMotionWindow, repeats: true) { [weak self] _ in
                self?._calculateMotionTypeLocked()
            }
        }
    }

    // MARK: - Motion type calculation

    @objc public func calculateMotionType() {
        stateQueue?.async { self._calculateMotionTypeLocked() }
    }

    @objc public func _calculateMotionTypeLocked() {
        guard let classifier = activityClassifier, classifier.isWindowReady() else { return }
        let newType = classifier.classifyWithSpeed(currentSpeed)
        _applyMotionType(fromClassifier: newType, confidence: 80, emit: true)
    }

    @objc public func _applyMotionType(fromClassifier type: String, confidence: Int, emit: Bool) {
        previousMotionType = motionType
        motionType = type

        if type != previousMotionType {
            lastTypeChangeAt = Date()
            sdConsecutiveStillWins = 0
            mdConsecutiveMovingWins = 0
        }

        if type == "still" {
            sdConsecutiveStillWins += 1
            mdConsecutiveMovingWins = 0
        } else {
            mdConsecutiveMovingWins += 1
            sdConsecutiveStillWins = 0
        }

        lastEmittedType = type
        lastEmittedConfidence = confidence
        lastConfidence = confidence

        if emit {
            let activity = TSMotionActivity(type: type, confidence: confidence)
            currentActivity = activity
            motionActivityChangedBlock.map { _ in }
            NotificationCenter.default.post(name: NSNotification.Name("TSMotionDetectorDidUpdateActivity"), object: activity)
        }
    }

    @objc public func _applySamplingIntervalLocked(_ interval: TimeInterval) {
        accelerometerUpdateInterval = interval
        motionManager?.accelerometerUpdateInterval = interval
    }

    @objc public func _recalcFromM7Locked() {
        guard let activity = motionActivity else { return }
        var type = "unknown"
        if activity.stationary { type = "still" }
        else if activity.walking { type = "walking" }
        else if activity.running { type = "running" }
        else if activity.automotive { type = "in_vehicle" }
        else if activity.cycling { type = "on_bicycle" }
        _applyMotionType(fromClassifier: type, confidence: Int(activity.confidence.rawValue) * 25, emit: true)
    }

    @objc public func _maybeAdjustSamplingForActivity(_ type: String) {
        switch type {
        case "still":
            _applySamplingIntervalLocked(0.5)
        case "walking", "running":
            _applySamplingIntervalLocked(0.1)
        default:
            _applySamplingIntervalLocked(0.2)
        }
    }

    // MARK: - TSMotionActivitySourceDelegate

    @objc public func activitySource(_ source: TSMotionActivitySource, didUpdate activity: CMMotionActivity) {
        stateQueue?.async {
            self.motionActivity = activity
            self._recalcFromM7Locked()
            self._maybeAdjustSamplingForActivity(self.motionType)
        }
    }

    @objc public func activitySourceDidUpdate(_ activity: TSMotionActivity) {
        stateQueue?.async {
            self.motionActivity = nil
            self._recalcFromM7Locked()
            self._maybeAdjustSamplingForActivity(self.motionType)
        }
    }

    // MARK: - Location / speed

    @objc public func setLocation(_ loc: CLLocation, isMoving moving: Bool) {
        location = loc
        currentSpeed = max(0, loc.speed)
        isMoving = moving
        activityClassifier?.updateSpeed(currentSpeed)
    }

    @objc public func updateSpeed(_ speed: Double) {
        currentSpeed = speed
        activityClassifier?.updateSpeed(speed)
    }

    @objc public func isMoving(_ moving: Bool) -> Bool {
        return isMoving
    }

    @objc public func threadSafeMotionType() -> String {
        var result = "unknown"
        stateQueue?.sync { result = self.motionType }
        return result
    }

    @objc public func threadSafeMotionActivity() -> TSMotionActivity? {
        var result: TSMotionActivity?
        stateQueue?.sync { result = self.currentActivity }
        return result
    }

    @objc public func classifyWithSpeed(_ speed: Double) -> String {
        return activityClassifier?.classifyWithSpeed(speed) ?? "unknown"
    }

    @objc public func shouldRequestLocationProbe() -> Bool {
        guard enabled else { return false }
        if let suppressUntil = mdSuppressUntil, Date() < suppressUntil { return false }
        if let lastProbe = mdLastProbeAt {
            return Date().timeIntervalSince(lastProbe) >= probeMinInterval
        }
        return true
    }

    @objc public func noteWillRequestLocationProbe() {
        mdLastProbeAt = Date()
    }

    public func requestMotionPermission(_ completion: @escaping (CMAuthorizationStatus) -> Void) {
        permissionMgr?.requestPermission(completion: completion)
    }

    @objc public func queryMotionActivityHistory() {
        guard let mgr = motionActivityManager else { return }
        let end = Date()
        let start = end.addingTimeInterval(-3600)
        mgr.queryActivityStarting(from: start, to: end, to: OperationQueue.main) { [weak self] (activities: [CMMotionActivity]?, error: Error?) in
            guard let self = self, let acts = activities else { return }
            for act in acts {
                self.motionActivityChangedBlock?(act)
            }
        }
    }

    @objc public func getDiagnosticsData() -> [String: Any] {
        return [
            "motionType": motionType,
            "isMoving": isMoving,
            "enabled": enabled,
            "lastEmittedType": lastEmittedType,
            "lastEmittedConfidence": lastEmittedConfidence,
            "sdConsecutiveStillWins": sdConsecutiveStillWins,
            "mdConsecutiveMovingWins": mdConsecutiveMovingWins
        ]
    }
}
