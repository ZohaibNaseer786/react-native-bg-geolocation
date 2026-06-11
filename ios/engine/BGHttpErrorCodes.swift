import Foundation

public let BGHttpServiceErrorDomain = "BGHttpServiceErrorDomain"
public let BGHttpErrorKeyUnderlying = "BGHttpErrorKeyUnderlying"
public let BGHttpErrorKeyStatus = "BGHttpErrorKeyStatus"
public let BGHttpErrorKeyResponseBody = "BGHttpErrorKeyResponseBody"
public let BGHttpErrorKeyURL = "BGHttpErrorKeyURL"
public let BGHttpErrorKeyFromURL = "BGHttpErrorKeyFromURL"
public let BGHttpErrorKeyToURL = "BGHttpErrorKeyToURL"

@objc public final class BGHttpErrorCodes: NSObject {

    @objc public class func localizedDescription(forErrorCode code: Int) -> String {
        switch code {
        case 1: return "Invalid URL"
        case 2: return "Network connection failed"
        case 3: return "Sync operation already in progress"
        case 4: return "HTTP response error"
        case 5: return "HTTP redirect disallowed"
        default: return ""
        }
    }

    @objc public class func error(withCode code: Int, description: String?, userInfo: [AnyHashable: Any]?) -> NSError {
        var info: [String: Any] = [:]
        info[NSLocalizedDescriptionKey] = description ?? localizedDescription(forErrorCode: code)
        if let userInfo = userInfo {
            for (key, value) in userInfo {
                if let key = key as? String { info[key] = value }
            }
        }
        return NSError(domain: BGHttpServiceErrorDomain, code: code, userInfo: info)
    }

    @objc public class func invalidURLError(_ url: String?) -> NSError {
        let userInfo: [AnyHashable: Any] = [BGHttpErrorKeyURL: url ?? ""]
        return error(withCode: 1, description: localizedDescription(forErrorCode: 1), userInfo: userInfo)
    }

    @objc public class func noNetworkError() -> NSError {
        return error(withCode: 2, description: localizedDescription(forErrorCode: 2), userInfo: nil)
    }

    @objc public class func syncInProgressError() -> NSError {
        return error(withCode: 3, description: localizedDescription(forErrorCode: 3), userInfo: nil)
    }

    @objc public class func responseError(withStatus status: Int, url: String?, bodyBytes: Any?, underlying: Error?) -> NSError {
        var userInfo: [AnyHashable: Any] = [BGHttpErrorKeyStatus: status]
        if let url = url { userInfo[BGHttpErrorKeyURL] = url }
        if let bodyBytes = bodyBytes { userInfo[BGHttpErrorKeyResponseBody] = bodyBytes }
        if let underlying = underlying { userInfo[BGHttpErrorKeyUnderlying] = underlying }
        return error(withCode: 4, description: localizedDescription(forErrorCode: 4), userInfo: userInfo)
    }

    @objc public class func redirectError(from fromURL: String?, to toURL: String?) -> NSError {
        let userInfo: [AnyHashable: Any] = [
            BGHttpErrorKeyFromURL: fromURL ?? "",
            BGHttpErrorKeyToURL: toURL ?? ""
        ]
        return error(withCode: 5, description: localizedDescription(forErrorCode: 5), userInfo: userInfo)
    }
}
