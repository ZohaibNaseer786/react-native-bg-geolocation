import Foundation
import os.log

@objc public class BGNativeLogger: NSObject {

    private static let subsystem = "com.transistorsoft.BGLocationManager"
    private static let category = "general"

    @objc public class func log(_ level: Int, tag: String, message: String) {
        if #available(iOS 14.0, *) {
            let logger = Logger(subsystem: subsystem, category: tag)
            switch level {
            case 0: break
            case 1: logger.error("\(message)")
            case 2: logger.warning("\(message)")
            case 3: logger.info("\(message)")
            case 4: logger.debug("\(message)")
            default: logger.log("\(message)")
            }
        } else {
            let prefix: String
            switch level {
            case 1: prefix = "ERROR"
            case 2: prefix = "WARN"
            case 3: prefix = "INFO"
            case 4: prefix = "DEBUG"
            default: prefix = "LOG"
            }
            print("[\(prefix)] [\(tag)] \(message)")
        }
    }

    @objc public class func error(_ tag: String, message: String) {
        log(1, tag: tag, message: message)
    }

    @objc public class func warn(_ tag: String, message: String) {
        log(2, tag: tag, message: message)
    }

    @objc public class func info(_ tag: String, message: String) {
        log(3, tag: tag, message: message)
    }

    @objc public class func debug(_ tag: String, message: String) {
        log(4, tag: tag, message: message)
    }
}
