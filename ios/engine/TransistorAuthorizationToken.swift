import Foundation
import UIKit

@objc public class TransistorAuthorizationToken: NSObject {

    @objc public var accessToken: String
    @objc public var refreshToken: String
    @objc public var expires: Date
    @objc public var apiUrl: String?
    @objc public var refreshUrl: String?

    private static let storagePrefix = "BGLocationManager_transistor_token_"

    @objc public class func storageKey(forHost host: String) -> String {
        return "\(storagePrefix)\(host)"
    }

    @objc public class func hasToken(forHost host: String) -> Bool {
        let key = storageKey(forHost: host)
        return UserDefaults.standard.dictionary(forKey: key) != nil
    }

    @objc public class func destroy(url: URL) {
        guard let host = url.host else { return }
        let key = storageKey(forHost: host)
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.synchronize()
    }

    @objc public class func findOrCreate(
        org: String,
        username: String,
        url: URL,
        framework: String,
        success: @escaping (_ token: TransistorAuthorizationToken) -> Void,
        failure: @escaping (_ error: Error) -> Void
    ) {
        guard let host = url.host else {
            failure(NSError(domain: "TransistorAuthorizationToken", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid URL: missing host"]))
            return
        }

        let key = storageKey(forHost: host)

        if let stored = UserDefaults.standard.dictionary(forKey: key) {
            let token = TransistorAuthorizationToken(dictionary: stored, forUrl: url)
            if token.expires > Date() {
                DispatchQueue.main.async { success(token) }
                return
            }
        }

        let registrationURL = buildRegistrationURL(baseURL: url)

        var request = URLRequest(url: registrationURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60.0

        let deviceInfo = BGDeviceInfo.sharedInstance
        let body: [String: Any] = [
            "org": org,
            "device": [
                "unique_id": UIDevice.current.identifierForVendor?.uuidString ?? "",
                "model": deviceInfo.model ?? "",
                "platform": "iOS",
                "manufacturer": "Apple",
                "version": deviceInfo.version ?? "",
                "framework": framework,
                "username": username
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { failure(error) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    failure(NSError(domain: "TransistorAuthorizationToken", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                }
                return
            }

            if httpResponse.statusCode == 200 {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    DispatchQueue.main.async {
                        failure(NSError(domain: "TransistorAuthorizationToken", code: -2,
                                        userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"]))
                    }
                    return
                }

                let token = TransistorAuthorizationToken(dictionary: json, forUrl: url)
                let stored = token.toDictionary()
                UserDefaults.standard.set(stored, forKey: key)
                UserDefaults.standard.synchronize()

                DispatchQueue.main.async { success(token) }
            } else {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    DispatchQueue.main.async {
                        failure(NSError(domain: "TransistorAuthorizationToken", code: httpResponse.statusCode,
                                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]))
                    }
                    return
                }
                let msg = json["error"] as? String ?? "HTTP \(httpResponse.statusCode)"
                DispatchQueue.main.async {
                    failure(NSError(domain: "TransistorAuthorizationToken", code: httpResponse.statusCode,
                                    userInfo: [NSLocalizedDescriptionKey: msg]))
                }
            }
        }
        task.resume()
    }

    private class func buildRegistrationURL(baseURL: URL) -> URL {
        var urlString = baseURL.absoluteString
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        let registrationPath = urlString + "/api/devices"
        return URL(string: registrationPath) ?? baseURL
    }

    @objc public init(accessToken: String, refreshToken: String, expires: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expires = expires
        super.init()
    }

    @objc public init(dictionary: [String: Any], forUrl url: URL) {
        self.accessToken = dictionary["access_token"] as? String ?? ""
        self.refreshToken = dictionary["refresh_token"] as? String ?? ""

        if let expiresAt = dictionary["expires_at"] as? Double {
            self.expires = Date(timeIntervalSince1970: expiresAt)
        } else if let expiresStr = dictionary["expires_at"] as? String {
            let formatter = ISO8601DateFormatter()
            self.expires = formatter.date(from: expiresStr) ?? Date.distantFuture
        } else {
            self.expires = Date.distantFuture
        }

        self.apiUrl = url.absoluteString
        if let baseUrl = dictionary["base_url"] as? String {
            self.refreshUrl = baseUrl + "/api/refresh_token"
        }
        super.init()
    }

    @objc public override init() {
        self.accessToken = ""
        self.refreshToken = ""
        self.expires = Date.distantFuture
        super.init()
    }

    @objc public func toDictionary() -> [String: Any] {
        return [
            "access_token": accessToken,
            "refresh_token": refreshToken,
            "expires_at": expires.timeIntervalSince1970,
            "api_url": apiUrl ?? ""
        ]
    }

    @objc public override var description: String {
        return "<TransistorAuthorizationToken accessToken=\(accessToken) expires=\(expires)>"
    }
}
