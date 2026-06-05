import Foundation

@objc public final class TSHttpRequest: NSObject {

    @objc public private(set) var records: [Any]
    @objc public var completion: ((TSHttpRequest, TSHttpResponse) -> Void)?
    @objc public private(set) var requestData: Any?
    @objc public private(set) var url: URL?

    @objc public static func execute(_ records: [Any], callback: @escaping (TSHttpRequest, TSHttpResponse) -> Void) -> TSHttpRequest {
        let request = TSHttpRequest(records: records, callback: callback)
        request.run()
        return request
    }

    @objc public init(records: [Any], callback: ((TSHttpRequest, TSHttpResponse) -> Void)?) {
        self.records = records
        super.init()
        let urlString = TSConfig.sharedInstance().http.url
        if !urlString.isEmpty {
            self.url = URL(string: urlString)
        }
        self.completion = callback
    }

    @objc public func run() {
        let config = TSConfig.sharedInstance()
        let http = config.http

        guard let url = url else { return }
        let request = NSMutableURLRequest(url: url,
                                          cachePolicy: .reloadIgnoringLocalCacheData,
                                          timeoutInterval: http.timeoutSeconds)
        request.httpMethod = http.method
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        // Build the JSON payload from the records' "location" entries.
        let rootProperty = http.rootProperty
        var payload: Any
        if http.batchSync {
            var array: [Any] = []
            for record in records {
                if let dict = record as? [AnyHashable: Any], let location = dict["location"] {
                    array.append(location)
                }
            }
            payload = array
        } else {
            payload = (records.first as? [AnyHashable: Any])?["location"] ?? [:]
        }

        var requestObject: Any
        if rootProperty == "." {
            requestObject = payload
        } else {
            requestObject = [rootProperty ?? "": payload]
        }

        // Merge #params (only valid when the payload is an object).
        let params = http.params
        if !params.isEmpty {
            if var dict = requestObject as? [AnyHashable: Any] {
                dict.merge(params) { _, new in new }
                requestObject = dict
            } else {
                let logger = TSLog.sharedInstance()
                if logger.shouldLog(2) {
                    let message = "Cannot attach HTTP #params to an HTTP request with JSON data of type [Array], not an {Object].  Specify an #httpRootProperty other than '.' (eg: 'data')"
                    logger.log(2, tag: 9, function: "-[TSHttpRequest run]", message: message)
                }
            }
        }

        // Custom headers.
        let headers = http.headers
        for (key, value) in headers {
            request.setValue(String(format: "%@", "\(value)"), forHTTPHeaderField: "\(key)")
        }

        // Authorization strategy: apply auth headers if configured.
        if let token = config.authorization.accessToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Serialize body.
        var jsonError: NSError?
        let body: Data?
        do {
            body = try JSONSerialization.data(withJSONObject: requestObject, options: [])
        } catch let error as NSError {
            jsonError = error
            body = nil
        }

        if let jsonError = jsonError {
            let logger = TSLog.sharedInstance()
            if logger.shouldLog(1) {
                let message = String(format: "JSON error composing HTTP POST data: %@", jsonError.localizedDescription)
                logger.log(1, tag: 0, function: "-[TSHttpRequest run]", message: message)
            }
            let response = TSHttpResponse(status: 200, data: nil, error: jsonError)
            completion?(self, response)
            return
        }

        guard let body = body else { return }

        let logger = TSLog.sharedInstance()
        if logger.shouldLog(1) {
            let bodyString = String(data: body, encoding: .utf8) ?? ""
            let message = String(format: "%@", bodyString)
            logger.log(1, tag: 0, function: "-[TSHttpRequest run]", message: message)
        }

        request.setValue(String(format: "%lu", body.count), forHTTPHeaderField: "Content-Length")
        request.httpBody = body

        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: request as URLRequest) { [weak self] (data, response, error) in
            guard let self = self else { return }
            let httpResponse = TSHttpResponse(data: data, response: response, error: error)
            self.completion?(self, httpResponse)
        }
        task.resume()
    }
}
