import Foundation

@objc public final class BGPowerSaveChangeEvent: NSObject {

    @objc public private(set) var isPowerSaveMode: Bool

    @objc public override init() {
        self.isPowerSaveMode = false
        super.init()
        self.isPowerSaveMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
