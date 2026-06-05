import Foundation

@objc public final class TSHttpEvent: NSObject {

    @objc public private(set) var isSuccess: Bool = false
    @objc public private(set) var statusCode: Int = 0
    @objc public private(set) var requestData: String?
    @objc public private(set) var responseText: String?
    @objc public private(set) var error: Error?

    @objc public init(statusCode: Int, requestData: String?, responseData: Data?, error: Error?) {
        super.init()
        self.isSuccess = (statusCode >= 200 && statusCode < 205)
        self.statusCode = statusCode
        self.requestData = requestData
        if let responseData = responseData {
            self.responseText = String(data: responseData, encoding: .utf8) ?? ""
        } else {
            self.responseText = ""
        }
        self.error = error
    }

    @objc public func toDictionary() -> [String: Any] {
        let dict = NSMutableDictionary()
        dict["success"] = isSuccess
        dict["status"] = statusCode
        dict["responseText"] = responseText ?? ""
        if let error = error as NSError? {
            dict["error"] = error.localizedDescription
        }
        return dict as! [String: Any]
    }
}
