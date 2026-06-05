import Foundation

public let TSHttpServiceErrorDomain = "TSHttpServiceErrorDomain"
public let TSHttpErrorKeyUnderlying = "TSHttpErrorKeyUnderlying"
public let TSHttpErrorKeyStatus = "TSHttpErrorKeyStatus"
public let TSHttpErrorKeyResponseBody = "TSHttpErrorKeyResponseBody"
public let TSHttpErrorKeyURL = "TSHttpErrorKeyURL"
public let TSHttpErrorKeyFromURL = "TSHttpErrorKeyFromURL"
public let TSHttpErrorKeyToURL = "TSHttpErrorKeyToURL"

@objc public final class TSHttpErrorCodes: NSObject {

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
        return NSError(domain: TSHttpServiceErrorDomain, code: code, userInfo: info)
    }

    @objc public class func invalidURLError(_ url: String?) -> NSError {
        let userInfo: [AnyHashable: Any] = [TSHttpErrorKeyURL: url ?? ""]
        return error(withCode: 1, description: localizedDescription(forErrorCode: 1), userInfo: userInfo)
    }

    @objc public class func noNetworkError() -> NSError {
        return error(withCode: 2, description: localizedDescription(forErrorCode: 2), userInfo: nil)
    }

    @objc public class func syncInProgressError() -> NSError {
        return error(withCode: 3, description: localizedDescription(forErrorCode: 3), userInfo: nil)
    }

    @objc public class func responseError(withStatus status: Int, url: String?, bodyBytes: Any?, underlying: Error?) -> NSError {
        var userInfo: [AnyHashable: Any] = [TSHttpErrorKeyStatus: status]
        if let url = url { userInfo[TSHttpErrorKeyURL] = url }
        if let bodyBytes = bodyBytes { userInfo[TSHttpErrorKeyResponseBody] = bodyBytes }
        if let underlying = underlying { userInfo[TSHttpErrorKeyUnderlying] = underlying }
        return error(withCode: 4, description: localizedDescription(forErrorCode: 4), userInfo: userInfo)
    }

    @objc public class func redirectError(from fromURL: String?, to toURL: String?) -> NSError {
        let userInfo: [AnyHashable: Any] = [
            TSHttpErrorKeyFromURL: fromURL ?? "",
            TSHttpErrorKeyToURL: toURL ?? ""
        ]
        return error(withCode: 5, description: localizedDescription(forErrorCode: 5), userInfo: userInfo)
    }
}
