import Foundation
import CoreLocation

@objc public class BGSamplingSession: NSObject {

    @objc public var active: Bool = false
    @objc public var startedAt: Date?
    @objc public var bestLocation: CLLocation?
    @objc public var collected: Int = 0

    @objc public override init() {
        super.init()
    }
}

@objc public class BGStreamState: NSObject {

    @objc public var request: BGStreamLocationRequest?
    @objc public var lastEmitAt: Date?
    @objc public var lastEmitted: CLLocation?
    @objc public var minInterval: TimeInterval = 1.0
    @objc public var startedAt: Date?
    @objc public var timeoutTimer: Timer?

    @objc public override init() {
        super.init()
    }
}

@objc public class BGLocationRequestService: NSObject, CLLocationManagerDelegate {

    private static var _sharedInstance: BGLocationRequestService?
    private static let instanceLock = NSLock()

    @objc public class func sharedInstance() -> BGLocationRequestService {
        instanceLock.lock()
        defer { instanceLock.unlock() }
        if _sharedInstance == nil { _sharedInstance = BGLocationRequestService() }
        return _sharedInstance!
    }

    @objc public class func configureShared(withLocationManager manager: CLLocationManager) {
        sharedInstance().manager = manager
        // The CLLocationManager delegate is owned by BGCLRouter, which forwards
        // location callbacks here. Do NOT assign manager.delegate.
    }

    // MARK: - State

    @objc public var manager: CLLocationManager?
    @objc public var session: BGSamplingSession?
    @objc public var streams: [Int: BGStreamState] = [:]
    @objc public var lastLocation: CLLocation?
    @objc public var lastErrorAt: Date?
    @objc public var lastTransientError: Error?
    @objc public var transientErrorCount: Int = 0
    @objc public var transientErrorTimer: Timer?
    @objc public var nextStreamId: Int = 1
    @objc public var sampleCount: Int = 0

    @objc public var errorGraceBase: TimeInterval = 5.0
    @objc public var errorGraceMax: TimeInterval = 60.0
    @objc public var errorBackoffFactor: Double = 2.0
    @objc public var errorGracePeriod: TimeInterval = 0

    var lockQueue: DispatchQueue?
    var callbackQueue: DispatchQueue?
    var eventBusTokens: [Int] = []
    var timeoutTimers: [String: Timer] = [:]

    private var completeListeners: [String: [Int: (CLLocation?) -> Void]] = [:]
    private var errorListeners: [String: [Int: (Error) -> Void]] = [:]
    private var sampleListeners: [String: [Int: (CLLocation) -> Void]] = [:]
    private var listenerToken = 0

    // Active getCurrentPosition requests, keyed by requestId. The request's own
    // success/failure blocks are driven directly from didUpdateLocations / the
    // timeout — these are the blocks the ObjC bridge passed down.
    private var positionRequests: [String: BGCurrentPositionRequest] = [:]
    private var positionSamples: [String: [CLLocation]] = [:]

    @objc public override init() {
        super.init()
        lockQueue = DispatchQueue(label: "BGLocationRequestService.lock")
        callbackQueue = DispatchQueue.main
    }

    @objc public init(locationManager: CLLocationManager) {
        self.manager = locationManager
        super.init()
        lockQueue = DispatchQueue(label: "BGLocationRequestService.lock")
        callbackQueue = DispatchQueue.main
    }

    @objc public func isActive() -> Bool {
        return session?.active == true || !streams.isEmpty || !positionRequests.isEmpty
    }

    @objc public func hasActiveStreams() -> Bool {
        return !streams.isEmpty
    }

    // MARK: - Listener registration

    @objc public func addCompleteListener(forType type: String, listener: @escaping (CLLocation?) -> Void) -> Int {
        listenerToken += 1
        if completeListeners[type] == nil { completeListeners[type] = [:] }
        completeListeners[type]![listenerToken] = listener
        return listenerToken
    }

    @objc public func addErrorListener(forType type: String, listener: @escaping (Error) -> Void) -> Int {
        listenerToken += 1
        if errorListeners[type] == nil { errorListeners[type] = [:] }
        errorListeners[type]![listenerToken] = listener
        return listenerToken
    }

    @objc public func addSampleListener(forType type: String, listener: @escaping (CLLocation) -> Void) -> Int {
        listenerToken += 1
        if sampleListeners[type] == nil { sampleListeners[type] = [:] }
        sampleListeners[type]![listenerToken] = listener
        return listenerToken
    }

    @objc public func removeCompleteListener(forType type: String, token: Int) {
        completeListeners[type]?.removeValue(forKey: token)
    }

    @objc public func removeErrorListener(forType type: String, token: Int) {
        errorListeners[type]?.removeValue(forKey: token)
    }

    @objc public func removeSampleListener(forType type: String, token: Int) {
        sampleListeners[type]?.removeValue(forKey: token)
    }

    @objc public func removeAllCompleteListeners(forType type: String) {
        completeListeners.removeValue(forKey: type)
    }

    @objc public func removeAllErrorListeners(forType type: String) {
        errorListeners.removeValue(forKey: type)
    }

    @objc public func removeAllSampleListeners(forType type: String) {
        sampleListeners.removeValue(forKey: type)
    }

    // MARK: - Location requests

    @objc public func requestLocation(_ request: BGCurrentPositionRequest) {
        lockQueue?.async {
            // Serve immediately from a fresh-enough cached fix when allowed.
            if request.maximumAge > 0, let cached = self.lastLocation {
                let age = -cached.timestamp.timeIntervalSinceNow
                let accuracyOK = request.desiredAccuracy <= 0 || cached.horizontalAccuracy <= request.desiredAccuracy
                if age <= (request.maximumAge / 1000.0) && accuracyOK {
                    self.deliverPositionLocked(request, location: cached)
                    return
                }
            }
            self.positionRequests[request.requestId] = request
            self.positionSamples[request.requestId] = []
            self.startUpdatingLocked()
            self.scheduleTimeoutLocked(forRequest: request)
        }
    }

    /// Build a BGLocation, optionally persist, and fire the request's success
    /// block on the callback queue. Caller must hold the lockQueue.
    private func deliverPositionLocked(_ request: BGCurrentPositionRequest, location: CLLocation) {
        let tsLocation = BGLocation(location: location, type: "current", extras: request.extras as? [String: Any])
        if request.persist {
            _ = BGLocationDAO.sharedInstance().create(tsLocation, error: nil)
        }
        let success = request.success
        callbackQueue?.async { success?(tsLocation) }
    }

    /// Resolve an in-flight position request with its best sample. lockQueue.
    private func finishPositionRequestLocked(_ requestId: String, location: CLLocation) {
        guard let request = positionRequests[requestId] else { return }
        clearTimeoutLockedForRequest(requestId)
        positionRequests.removeValue(forKey: requestId)
        positionSamples.removeValue(forKey: requestId)
        deliverPositionLocked(request, location: location)
        maybeStopUpdatesLocked()
    }

    /// Fail an in-flight position request with a CLError-style code. lockQueue.
    private func failPositionRequestLocked(_ requestId: String, code: Int) {
        guard let request = positionRequests[requestId] else { return }
        clearTimeoutLockedForRequest(requestId)
        positionRequests.removeValue(forKey: requestId)
        positionSamples.removeValue(forKey: requestId)
        let failure = request.failure
        callbackQueue?.async { failure?(code) }
        maybeStopUpdatesLocked()
    }

    @objc public func startStream(_ request: BGStreamLocationRequest) -> Int {
        let streamId = nextStreamId
        nextStreamId += 1
        let state = BGStreamState()
        state.request = request
        state.startedAt = Date()
        state.minInterval = TimeInterval(request.interval) / 1000.0
        lockQueue?.async {
            self.streams[streamId] = state
            self.startUpdatingLocked()
        }
        return streamId
    }

    @objc public func stopStream(_ streamId: Int) {
        lockQueue?.async {
            self.streams.removeValue(forKey: streamId)
            self.maybeStopUpdatesLocked()
        }
    }

    @objc public func stopAllStreams() {
        lockQueue?.async {
            self.streams.removeAll()
            self.maybeStopUpdatesLocked()
        }
    }

    @objc public func cancelAllRequests() {
        lockQueue?.async {
            self.session = nil
            self.streams.removeAll()
            self.stopUpdatingLocked()
            self.cancelAllTimeouts()
        }
    }

    @objc public func cancelRequest(_ requestId: String) {
        lockQueue?.async {
            self.timeoutTimers[requestId]?.invalidate()
            self.timeoutTimers.removeValue(forKey: requestId)
            self.maybeEndSessionLocked()
        }
    }

    @objc public func cancelLockedRequest(_ requestId: String, error: Error?) {
        timeoutTimers[requestId]?.invalidate()
        timeoutTimers.removeValue(forKey: requestId)
        if let error = error {
            emitError(error, forRequest: requestId)
        }
        maybeEndSessionLocked()
    }

    // MARK: - Update control

    @objc public func startUpdatingLocked() {
        DispatchQueue.main.async {
            self.manager?.startUpdatingLocation()
        }
    }

    @objc public func stopUpdatingLocked() {
        DispatchQueue.main.async {
            self.manager?.stopUpdatingLocation()
        }
    }

    @objc public func maybeStopUpdatesLocked() {
        guard !isActive() else { return }
        // The CLLocationManager is shared with BGTrackingService. If tracking is
        // running, hand control back to it rather than blindly stopping updates
        // (which would silently break active background tracking).
        let tracking = BGTrackingService.sharedInstance()
        if tracking.isEnabled {
            tracking.restoreUpdatingState()
        } else {
            stopUpdatingLocked()
        }
    }

    @objc public func maybeEndSessionLocked() {
        if session?.active == true && (timeoutTimers.isEmpty) {
            endSessionLocked()
        }
    }

    @objc public func endSessionLocked() {
        session?.active = false
        session = nil
        maybeStopUpdatesLocked()
    }

    // MARK: - Timeout management

    @objc public func scheduleTimeoutLocked(forRequest request: BGCurrentPositionRequest) {
        let timeout = request.timeout
        guard timeout > 0 else { return }
        let id = request.requestId
        DispatchQueue.main.async {
            let timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                self?.lockQueue?.async {
                    guard let self = self else { return }
                    // On timeout, return the best sample collected so far; only
                    // fail (code 408) if nothing arrived at all.
                    if let best = (self.positionSamples[id] ?? []).min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) {
                        self.finishPositionRequestLocked(id, location: best)
                    } else {
                        self.failPositionRequestLocked(id, code: 408)
                    }
                }
            }
            // Keep all timeoutTimers mutations on lockQueue (clear runs there too).
            self.lockQueue?.async { self.timeoutTimers[id] = timer }
        }
    }

    @objc public func clearTimeoutLockedForRequest(_ requestId: String) {
        if let timer = timeoutTimers.removeValue(forKey: requestId) {
            DispatchQueue.main.async { timer.invalidate() }
        }
    }

    func cancelAllTimeouts() {
        for (_, timer) in timeoutTimers { timer.invalidate() }
        timeoutTimers.removeAll()
    }

    // MARK: - Satisfaction

    @objc public func trySatisfyRequest(_ request: BGCurrentPositionRequest, with location: CLLocation) -> Bool {
        let age = -location.timestamp.timeIntervalSinceNow
        if age > request.maximumAge { return false }
        if location.horizontalAccuracy > request.desiredAccuracy && request.desiredAccuracy > 0 { return false }
        completeRequest(request.requestId, success: true, location: location, error: nil)
        return true
    }

    @objc public func trySatisfyRequestsLockedWith(_ location: CLLocation) {
        let id = session?.active == true ? "session" : nil
        if let id = id {
            sampleCount += 1
            emitSample(location, forRequest: id)
        }
    }

    @objc public func completeRequest(_ requestId: String, success: Bool, location: CLLocation?, error: Error?) {
        clearTimeoutLockedForRequest(requestId)
        if success {
            emitComplete(location, forRequest: requestId)
        } else if let error = error {
            emitError(error, forRequest: requestId)
        }
        maybeEndSessionLocked()
    }

    // MARK: - Emission

    @objc public func emitComplete(_ location: CLLocation?, forRequest requestId: String) {
        for (_, listener) in (completeListeners[requestId] ?? [:]) {
            callbackQueue?.async { listener(location) }
        }
    }

    @objc public func emitError(_ error: Error, forRequest requestId: String) {
        for (_, listener) in (errorListeners[requestId] ?? [:]) {
            callbackQueue?.async { listener(error) }
        }
    }

    @objc public func emitSample(_ location: CLLocation, forRequest requestId: String) {
        for (_, listener) in (sampleListeners[requestId] ?? [:]) {
            callbackQueue?.async { listener(location) }
        }
    }

    // MARK: - Transient error handling

    @objc public func startTransientErrorGraceTimerLocked() {
        let period = min(errorGraceBase * pow(errorBackoffFactor, Double(transientErrorCount)), errorGraceMax)
        errorGracePeriod = period
        DispatchQueue.main.async {
            self.transientErrorTimer?.invalidate()
            self.transientErrorTimer = Timer.scheduledTimer(withTimeInterval: period, repeats: false) { [weak self] _ in
                self?.cancelTransientErrorGraceTimerLocked()
                self?.transientErrorCount = 0
            }
        }
    }

    @objc public func cancelTransientErrorGraceTimerLocked() {
        transientErrorTimer?.invalidate()
        transientErrorTimer = nil
    }

    @objc public func currentGraceWindowLocked() -> TimeInterval {
        return errorGracePeriod
    }

    // MARK: - CLLocationManagerDelegate

    @objc public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        lockQueue?.async {
            // getCurrentPosition: collect samples; resolve once a fix is accurate
            // enough or the requested sample count is reached. Iterate a snapshot
            // because finishPositionRequestLocked mutates positionRequests.
            for (id, request) in Array(self.positionRequests) {
                self.positionSamples[id, default: []].append(location)
                let samples = self.positionSamples[id] ?? [location]
                let best = samples.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) ?? location
                let accuracyOK = request.desiredAccuracy <= 0 || best.horizontalAccuracy <= request.desiredAccuracy
                if accuracyOK || samples.count >= max(1, request.samples) {
                    self.finishPositionRequestLocked(id, location: best)
                }
            }

            // watchPosition streams: drive each stream's success block, throttled
            // by its minInterval.
            for (_, state) in self.streams {
                let now = Date()
                if let lastEmit = state.lastEmitAt {
                    guard now.timeIntervalSince(lastEmit) >= state.minInterval else { continue }
                }
                state.lastEmitAt = now
                state.lastEmitted = location
                let success = state.request?.success
                self.callbackQueue?.async { success?(location) }
            }
        }
    }

    @objc public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastErrorAt = Date()
        lastTransientError = error
        lockQueue?.async {
            self.transientErrorCount += 1
            self.startTransientErrorGraceTimerLocked()
        }
    }

    @available(iOS 14.0, *)
    @objc public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    }

    @objc public func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
    }

    // MARK: - CL mutation

    @objc public func _mutateCLAsync(_ block: @escaping (CLLocationManager) -> Void) {
        DispatchQueue.main.async {
            guard let mgr = self.manager else { return }
            block(mgr)
        }
    }
}
