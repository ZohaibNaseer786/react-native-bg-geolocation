import Foundation

@objc public final class TSEnv: NSObject {

    @objc public var isTesting: Bool = false

    @objc public static let sharedInstance = TSEnv()

    @objc public override init() {
        super.init()
        let environment = ProcessInfo.processInfo.environment
        let xpcServiceName = environment["XPC_SERVICE_NAME"]
        if let xpcServiceName = xpcServiceName, xpcServiceName.hasSuffix("xctest") {
            self.isTesting = true
        }
    }
}
