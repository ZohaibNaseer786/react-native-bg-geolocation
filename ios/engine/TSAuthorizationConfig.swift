import Foundation

@objc public class TSAuthorizationConfig: TSConfigModuleBase {

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

    @objc public override func propertySpecs() -> [TSPropertySpecImpl] {
        return [
            TSPropertySpec(name: "strategy", type: "string"),
            TSPropertySpec(name: "accessToken", type: "string"),
            TSPropertySpec(name: "refreshToken", type: "string"),
            TSPropertySpec(name: "refreshUrl", type: "string"),
            TSPropertySpec(name: "refreshHeaders", type: "object"),
            TSPropertySpec(name: "refreshPayload", type: "object"),
            TSPropertySpec(name: "expires", type: "date")
        ]
    }

    @objc public func apply(_ dict: [String: Any]) {
        updateWithDictionary(dict)
    }
}
