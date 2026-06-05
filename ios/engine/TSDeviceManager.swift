import Foundation
#if canImport(UIKit)
import UIKit
#endif

@objc public final class TSDeviceManager: NSObject {

    @objc public static let sharedInstance = TSDeviceManager()

    @objc public override init() {
        super.init()
    }

    @objc public func startMonitoring() {
        let logger = TSLog.sharedInstance()
        if logger.shouldLog(3) {
            logger.log(3, tag: 4, function: "-[TSDeviceManager startMonitoring]", message: "")
        }
        UIDevice.current.isBatteryMonitoringEnabled = false
        UIDevice.current.isBatteryMonitoringEnabled = true

        NotificationCenter.default.removeObserver(self,
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self,
            selector: #selector(didChangePowerMode(_:)),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil)
    }

    @objc public func stopMonitoring() {
        let logger = TSLog.sharedInstance()
        if logger.shouldLog(3) {
            logger.log(3, tag: 5, function: "-[TSDeviceManager stopMonitoring]", message: "")
        }
        UIDevice.current.isBatteryMonitoringEnabled = false
        NotificationCenter.default.removeObserver(self,
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil)
    }

    @objc public func batteryLevel() -> Float {
        return UIDevice.current.batteryLevel
    }

    @objc public func batteryState() -> Int {
        return UIDevice.current.batteryState.rawValue
    }

    @objc public func isLowPowerMode() -> Bool {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    @objc public func didChangePowerMode(_ notification: Notification) {
        let lowPower = isLowPowerMode()
        let logger = TSLog.sharedInstance()
        if logger.shouldLog(3) {
            let message = String(format: "%@", lowPower ? "ENABLED" : "DISABLED")
            logger.log(3, tag: 0, function: "-[TSDeviceManager didChangePowerMode:]", message: message)
        }
        let payload = TSPowerSaveChangeEvent()
        TSEventBus.sharedInstance().trigger(TSEventNamePowerSaveChange, payload: payload)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
