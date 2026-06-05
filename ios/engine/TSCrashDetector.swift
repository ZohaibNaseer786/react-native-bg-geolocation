import Foundation
import CoreMotion

@objc public class TSCrashDetector: NSObject {

    private static var _sharedInstance: TSCrashDetector?
    private static let lock = NSLock()

    @objc public var motionManager: CMMotionManager?

    @objc public var accelerometerThresholdHigh: Double = 3.0
    @objc public var accelerometerThresholdLow: Double = 1.0
    @objc public var accelerometerHysteresisDuration: Double = 0.5
    @objc public var accelerometerTimestamp: Double = 0
    @objc public var accelerometerTriggered: Bool = false
    @objc public var accelerometerDidCrash: Bool = false

    @objc public var gyroscopeThresholdHigh: Double = 10.0
    @objc public var gyroscopeThresholdLow: Double = 2.0
    @objc public var gyroscopeHysteresisDuration: Double = 0.5
    @objc public var gyroscopeTimestamp: Double = 0
    @objc public var gyroscopeTriggered: Bool = false
    @objc public var gyroscopeDidCrash: Bool = false

    @objc public var magnetometerThresholdHigh: Double = 100.0
    @objc public var magnetometerThresholdLow: Double = 20.0
    @objc public var magnetometerTimestamp: Double = 0
    @objc public var magnetometerTriggered: Bool = false
    @objc public var magnetometerDidCrash: Bool = false

    @objc public class func sharedInstance() -> TSCrashDetector {
        lock.lock()
        defer { lock.unlock() }
        if _sharedInstance == nil {
            _sharedInstance = TSCrashDetector()
        }
        return _sharedInstance!
    }

    @objc public override init() {
        super.init()
        motionManager = CMMotionManager()
    }

    @objc public func start() {
        guard let mgr = motionManager else { return }
        if mgr.isAccelerometerAvailable {
            mgr.accelerometerUpdateInterval = 0.1
            mgr.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                if let data = data { self?.processAccelerometerData(data) }
            }
        }
        if mgr.isGyroAvailable {
            mgr.gyroUpdateInterval = 0.1
            mgr.startGyroUpdates(to: .main) { [weak self] data, _ in
                if let data = data { self?.processGyroscopeData(data) }
            }
        }
        if mgr.isMagnetometerAvailable {
            mgr.magnetometerUpdateInterval = 0.1
            mgr.startMagnetometerUpdates(to: .main) { [weak self] data, _ in
                if let data = data { self?.processMagnetometerData(data) }
            }
        }
    }

    @objc public func stop() {
        motionManager?.stopAccelerometerUpdates()
        motionManager?.stopGyroUpdates()
        motionManager?.stopMagnetometerUpdates()
    }

    @objc public func processAccelerometerData(_ data: CMAccelerometerData) {
        let magnitude = sqrt(data.acceleration.x * data.acceleration.x +
                            data.acceleration.y * data.acceleration.y +
                            data.acceleration.z * data.acceleration.z)
        if magnitude > accelerometerThresholdHigh {
            accelerometerTimestamp = data.timestamp
            accelerometerTriggered = true
        } else if magnitude < accelerometerThresholdLow && accelerometerTriggered {
            let elapsed = data.timestamp - accelerometerTimestamp
            if elapsed <= accelerometerHysteresisDuration {
                accelerometerDidCrash = true
                handleCrashDetected()
            }
            accelerometerTriggered = false
        }
    }

    @objc public func processGyroscopeData(_ data: CMGyroData) {
        let magnitude = sqrt(data.rotationRate.x * data.rotationRate.x +
                            data.rotationRate.y * data.rotationRate.y +
                            data.rotationRate.z * data.rotationRate.z)
        if magnitude > gyroscopeThresholdHigh {
            gyroscopeTimestamp = data.timestamp
            gyroscopeTriggered = true
        } else if magnitude < gyroscopeThresholdLow && gyroscopeTriggered {
            let elapsed = data.timestamp - gyroscopeTimestamp
            if elapsed <= gyroscopeHysteresisDuration {
                gyroscopeDidCrash = true
                handleCrashDetected()
            }
            gyroscopeTriggered = false
        }
    }

    @objc public func processMagnetometerData(_ data: CMMagnetometerData) {
        let magnitude = sqrt(data.magneticField.x * data.magneticField.x +
                            data.magneticField.y * data.magneticField.y +
                            data.magneticField.z * data.magneticField.z)
        if magnitude > magnetometerThresholdHigh {
            magnetometerTimestamp = data.timestamp
            magnetometerTriggered = true
            magnetometerDidCrash = true
            handleCrashDetected()
        }
    }

    @objc public func handleCrashDetected() {
        NotificationCenter.default.post(name: NSNotification.Name("TSCrashDetected"), object: self)
    }
}
