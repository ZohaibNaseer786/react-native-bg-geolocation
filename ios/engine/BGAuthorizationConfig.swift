import Foundation

@objc public class BGAuthorizationConfig: BGConfigModuleBase {

    @objc public var strategy: String = "JWT"
    @objc public var accessToken: String?
    @objc public var refreshToken: String?
    @objc public var refreshUrl: String?
    @objc public var refreshHeaders: [String: String] = [:]
    @objc public var refreshPayload: [String: Any] = [:]
    @objc public var expires: Date?

    @objc public override func applyDefaults() {
        strategy = "JWT"
        accessToken = nil
        refreshToken = nil
        refreshUrl = nil
        refreshHeaders = [:]
        refreshPayload = [:]
        expires = nil
    }

    @objc public func moduleKey() -> String {
        return "authorization"
    }

    @objc public override func deprecatedPropertyMappings() -> [String: String] {
        return [:]
    }

    @objc public override func sensitivePropertyNames() -> [String] {
        return ["accessToken", "refreshToken"]
    }

    @objc public override func propertySpecs() -> [BGPropertySpecImpl] {
        return [
            BGPropertySpec(name: "strategy", type: "string"),
            BGPropertySpec(name: "accessToken", type: "string"),
            BGPropertySpec(name: "refreshToken", type: "string"),
            BGPropertySpec(name: "refreshUrl", type: "string"),
            BGPropertySpec(name: "refreshHeaders", type: "object"),
            BGPropertySpec(name: "refreshPayload", type: "object"),
            BGPropertySpec(name: "expires", type: "date")
        ]
    }

    @objc public func apply(_ dict: [String: Any]) {
        updateWithDictionary(dict)
    }
}
