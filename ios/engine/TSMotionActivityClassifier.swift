import Foundation
import CoreMotion

@objc public class TSMotionActivityClassifier: NSObject {

    @objc public var sampleInterval: Double = 0.1
    @objc public var samplesPerWindow: Int = 50
    @objc public var windowSeconds: Double = 5.0
    @objc public var n: Int = 0
    @objc public var decay: Double = 0.95

    @objc public var sumMag: Double = 0
    @objc public var sumMag2: Double = 0
    @objc public var sumGyro2: Double = 0
    @objc public var lastMag: Double = 0
    @objc public var hasLastMag: Bool = false
    @objc public var jerkSum: Double = 0
    @objc public var jerkStill: Double = 0.05
    @objc public var jerkShakeThreshold: Double = 2.0
    @objc public var varStill: Double = 0.01
    @objc public var gyroShake: Double = 0.5
    @objc public var gyroStill: Double = 0.05

    @objc public var gzWalk_c: Double = 0
    @objc public var gzWalk_s: Double = 0
    @objc public var gzWalk_q1: Double = 0
    @objc public var gzWalk_q2: Double = 0
    @objc public var gzWalk_pow: Double = 0

    @objc public var gzRun_c: Double = 0
    @objc public var gzRun_s: Double = 0
    @objc public var gzRun_q1: Double = 0
    @objc public var gzRun_q2: Double = 0
    @objc public var gzRun_pow: Double = 0

    @objc public var walkWins: Int = 0
    @objc public var runWins: Int = 0
    @objc public var lastSpeed: Double = 0
    @objc public var maxWalkSpeed: Double = 3.0
    @objc public var maxRunSpeed: Double = 12.0
    @objc public var minSpeed: Double = 0.5
    @objc public var cadenceConfirmWindows: Int = 3

    @objc public override init() {
        super.init()
    }

    @objc public func configureWithSampleInterval(_ interval: Double, windowSeconds: Double) {
        self.sampleInterval = interval
        self.windowSeconds = windowSeconds
        self.samplesPerWindow = Int(windowSeconds / interval)
        reset()
    }

    @objc public func ingestAcceleration(_ data: CMAccelerometerData) {
        let ax = data.acceleration.x
        let ay = data.acceleration.y
        let az = data.acceleration.z
        let mag = sqrt(ax*ax + ay*ay + az*az)

        if hasLastMag {
            let jerk = abs(mag - lastMag) / sampleInterval
            jerkSum = jerkSum * decay + jerk
            sumGyro2 = sumGyro2 * decay
        }

        sumMag = sumMag * decay + mag
        sumMag2 = sumMag2 * decay + mag * mag
        lastMag = mag
        hasLastMag = true
        n = min(n + 1, samplesPerWindow)
    }

    @objc public func ingestRotationRate(_ data: CMGyroData) {
        let rx = data.rotationRate.x
        let ry = data.rotationRate.y
        let rz = data.rotationRate.z
        let gyroMag = sqrt(rx*rx + ry*ry + rz*rz)
        sumGyro2 = sumGyro2 * decay + gyroMag * gyroMag
    }

    @objc public func isWindowReady() -> Bool {
        return n >= samplesPerWindow
    }

    @objc public func classifyWithSpeed(_ speed: Double) -> String {
        lastSpeed = speed
        if speed < minSpeed { return "still" }
        if speed <= maxWalkSpeed { return "walking" }
        if speed <= maxRunSpeed { return "running" }
        return "in_vehicle"
    }

    @objc public func updateSpeed(_ speed: Double) {
        lastSpeed = speed
    }

    @objc public func reset() {
        n = 0
        sumMag = 0
        sumMag2 = 0
        sumGyro2 = 0
        jerkSum = 0
        hasLastMag = false
        walkWins = 0
        runWins = 0
    }
}
