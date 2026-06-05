import Foundation
import SystemConfiguration

public typealias TSReachabilityCallback = (_ hasConnection: Bool) -> Void

@objc public class TSReachability: NSObject {

    private var reachability: SCNetworkReachability?
    private var callback: TSReachabilityCallback?
    private var isMonitoring: Bool = false

    @objc public class func reachability(forHostName host: String) -> TSReachability {
        return TSReachability(host: host)
    }

    @objc public init(host: String) {
        reachability = SCNetworkReachabilityCreateWithName(nil, host)
        super.init()
    }

    @objc public override init() {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        reachability = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }
        super.init()
    }

    @objc public func startMonitoring(callback: @escaping TSReachabilityCallback) {
        self.callback = callback
        isMonitoring = true
        checkReachability()
    }

    @objc public func stopMonitoring() {
        isMonitoring = false
        callback = nil
    }

    @objc public func isReachable() -> Bool {
        guard let reachability = reachability else { return false }
        var flags = SCNetworkReachabilityFlags()
        SCNetworkReachabilityGetFlags(reachability, &flags)
        return flags.contains(.reachable) && !flags.contains(.connectionRequired)
    }

    private func checkReachability() {
        callback?(isReachable())
    }

    @objc public func hasNetworkConnection() -> Bool {
        return isReachable()
    }
}
