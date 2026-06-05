import Foundation

@objc public final class TSProviderChangeEvent: NSObject {

    @objc public private(set) var gps: Bool
    @objc public private(set) var network: Bool
    @objc public private(set) var enabled: Bool
    @objc public private(set) var status: Int32
    @objc public private(set) var accuracyAuthorization: Int

    @objc public override init() {
        let manager = TSLocationManager.sharedInstance()
        let auth = TSLocationAuthorization.sharedInstance()
        self.gps = true
        self.network = true
        self.status = Int32(auth.authorizationStatus.rawValue)
        self.enabled = manager.enabled
        self.accuracyAuthorization = auth.accuracyAuthorization
        super.init()
    }

    @objc public func toDictionary() -> [String: Any] {
        return [
            "enabled": enabled,
            "network": network,
            "gps": gps,
            "status": Int(status),
            "accuracyAuthorization": accuracyAuthorization
        ]
    }
}
