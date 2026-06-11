import Foundation

@objc public class BGAuthorization: NSObject {

    @objc public var strategy: String = "JWT"
    @objc public var accessToken: String?
    @objc public var refreshToken: String?
    @objc public var refreshUrl: String?
    @objc public var refreshHeaders: [String: String] = [:]
    @objc public var refreshPayload: [String: Any] = [:]
    @objc public var expires: Date?

    @objc public var accessRE: String?
    @objc public var accessTokenRE: String?
    @objc public var refreshTokenRE: String?
    @objc public var refreshRenewRE: String?
    @objc public var expiresRE: String?

    @objc public var config: BGAuthorizationConfig?

    @objc public override init() {
        super.init()
    }

    @objc public func applyResponseData(_ data: [String: Any]) {
        if let token = resolveValue(data, pattern: accessTokenRE) ?? data["access_token"] as? String {
            accessToken = token
        }
        if let refresh = resolveValue(data, pattern: refreshTokenRE) ?? data["refresh_token"] as? String {
            refreshToken = refresh
        }
        if let expiry = resolveValue(data, pattern: expiresRE) ?? data["expires_at"] as? String {
            let formatter = ISO8601DateFormatter()
            expires = formatter.date(from: expiry)
        }
    }

    private func resolveValue(_ data: [String: Any], pattern: String?) -> String? {
        guard let pattern = pattern, !pattern.isEmpty else { return nil }
        return data[pattern] as? String
    }

    public func refreshAuthorization(_ headers: inout [String: String], statusCode: Int) -> Bool {
        guard statusCode == 401, let refreshUrl = refreshUrl, !refreshUrl.isEmpty else { return false }
        return true
    }

    @objc public func resolve(
        _ request: URLRequest,
        success: @escaping (_ request: URLRequest) -> Void,
        failure: @escaping (_ error: Error) -> Void
    ) {
        var req = request
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        success(req)
    }

    @objc public func toDictionary() -> [String: Any] {
        return toDictionary(false)
    }

    @objc public func toDictionary(_ redact: Bool) -> [String: Any] {
        var dict: [String: Any] = ["strategy": strategy]
        if redact {
            dict["accessToken"] = "**redacted**"
            dict["refreshToken"] = "**redacted**"
        } else {
            if let t = accessToken { dict["accessToken"] = t }
            if let t = refreshToken { dict["refreshToken"] = t }
        }
        if let u = refreshUrl { dict["refreshUrl"] = u }
        if let e = expires { dict["expires"] = e.timeIntervalSince1970 }
        return dict
    }

    @objc public func toString() -> String {
        return "<BGAuthorization strategy=\(strategy)>"
    }

    @objc public override var description: String {
        return toString()
    }
}
