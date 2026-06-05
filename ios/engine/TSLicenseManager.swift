// TSLicenseManager — stub for our open source build.
// The real TSLicenseManager is replaced with a no-op so TSConfig compiles.
// This package has no billing, no license check, no banner — it is a clean
// open implementation built from the provided source reference.

import Foundation
import UIKit

@objc public class TSLicenseManager: NSObject {

    private static let lock = NSLock()
    private static var _shared: TSLicenseManager?

    @objc public class func sharedManager() -> TSLicenseManager {
        lock.lock()
        defer { lock.unlock() }
        if _shared == nil { _shared = TSLicenseManager() }
        return _shared!
    }

    /// No-op — this build has no license requirement.
    @objc public func validateLicense() { }

    @objc public class func hasEntitlement(_ name: String) -> Bool { return true }
    @objc public class func tokenHasEntitlement(_ token: String) -> Bool { return true }
}
