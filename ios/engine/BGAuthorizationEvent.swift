import Foundation

@objc public final class BGAuthorizationEvent: NSObject {

    @objc public private(set) var status: Int
    @objc public private(set) var error: Error?
    @objc public private(set) var response: Any?

    @objc public init(response: Any?, status: Int) {
        self.status = status
        self.error = nil
        self.response = response
        super.init()
    }

    @objc public init(error: Error?, status: Int) {
        self.status = status
        self.error = error
        self.response = [AnyHashable: Any]()
        super.init()
    }

    @objc public func toDictionary() -> [String: Any] {
        if let error = error {
            return [
                "status": status,
                "success": false,
                "error": (error as NSError).localizedDescription,
                "response": NSNull()
            ]
        } else {
            return [
                "status": status,
                "success": true,
                "error": NSNull(),
                "response": response ?? NSNull()
            ]
        }
    }
}
