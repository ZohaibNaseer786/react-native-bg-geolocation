import Foundation
#if canImport(UIKit)
import UIKit
#endif

@objc public final class TSDeviceInfo: NSObject {

    @objc public var model: String?
    @objc public var manufacturer: String?
    @objc public var platform: String?
    @objc public var version: String?

    @objc public static let sharedInstance = TSDeviceInfo()

    @objc public override init() {
        super.init()
        let device = UIDevice.current
        self.model = getDeviceId()
        self.platform = device.systemName
        self.manufacturer = "Apple"
        self.version = device.systemVersion
    }

    @objc public func toDictionary() -> [String: Any] {
        return [
            "model": model ?? "",
            "platform": platform ?? "",
            "manufacturer": "Apple",
            "version": version ?? "",
            "framework": "native"
        ]
    }

    @objc public func toDictionary(_ framework: String) -> [String: Any] {
        var dict = toDictionary()
        dict["framework"] = framework
        return dict
    }

    @objc public func getDeviceId() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        if machine == "i386" || machine == "x86_64" {
            let simulatorModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
            return String(format: "%s(%@)", simulatorModel, machine)
        }
        return machine
    }
}
