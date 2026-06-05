import Foundation

@objc public final class TSHttpResponse: NSObject {

    @objc public var error: Error?
    @objc public var data: Data?
    @objc public var response: URLResponse?
    @objc public var status: Int = 0

    @objc public init(data: Data?, response: URLResponse?, error: Error?) {
        super.init()
        self.data = data
        self.response = response
        self.error = error
        if let httpResponse = response as? HTTPURLResponse {
            self.status = httpResponse.statusCode
        }
        handleResponse()
    }

    @objc public init(status: Int, data: Data?, error: Error?) {
        super.init()
        self.data = data
        self.response = nil
        self.error = error
        self.status = status
        handleResponse()
    }

    @objc public func handleResponse() {
        let config = TSConfig.sharedInstance()
        var requestURL: URL? = nil
        let urlString = config.http.url
        if !urlString.isEmpty {
            requestURL = URL(string: urlString)
        }

        // Redirect detection (301, 302, 307, 308) → flag redirect error.
        if [301, 302, 307, 308].contains(status) {
            let requestUrlString = requestURL?.absoluteString ?? ""
            let responseUrlString = (response as? HTTPURLResponse)?.url?.absoluteString ?? ""
            if !requestUrlString.isEmpty && !responseUrlString.isEmpty {
                self.error = NSError(domain: NSURLErrorDomain, code: status, userInfo: [NSLocalizedDescriptionKey: "Redirect from \(requestUrlString) to \(responseUrlString)"])
            }
        }

        // NSURLErrorUserCancelledAuthentication (-1012) → treat as 401.
        if let err = error as NSError?, err.code == -1012 {
            self.status = 401
        } else if [200, 201, 204].contains(status) {
            // Success — log and return.
            let logger = TSLog.sharedInstance()
            if logger.shouldLog(3) {
                let message = String(format: "Response: %ld", status)
                logger.log(3, tag: 1, function: "-[TSHttpResponse handleResponse]", message: message)
            }
            return
        } else if status == 410 {
            // Gone — destroy auth token for host if present.
            if let host = requestURL?.host, !host.isEmpty,
               let hostURL = URL(string: "https://\(host)") {
                if TransistorAuthorizationToken.hasToken(forHost: host) {
                    TransistorAuthorizationToken.destroy(url: hostURL)
                }
            }
        }

        // Build a descriptive error for any non-success response.
        var bodyString = ""
        if let data = data {
            bodyString = String(data: data, encoding: .utf8) ?? ""
        }
        var message = String(format: "HTTP ERROR: %ld", status)
        if !bodyString.isEmpty {
            message = message + String(format: "* %@\n", bodyString)
        }
        if let err = error as NSError? {
            message = message + String(format: "* %@\n*\n%@", err.localizedDescription, err.userInfo)
        }

        let logger = TSLog.sharedInstance()
        if logger.shouldLog(2) {
            let logMessage = String(format: "%@", message)
            logger.log(2, tag: 9, function: "-[TSHttpResponse handleResponse]", message: logMessage)
        }

        if error == nil {
            self.error = NSError(domain: NSURLErrorDomain,
                                 code: status,
                                 userInfo: [NSUnderlyingErrorKey: message])
        }
    }
}
