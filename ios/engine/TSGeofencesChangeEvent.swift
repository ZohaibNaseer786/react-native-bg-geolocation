import Foundation

@objc public final class TSGeofencesChangeEvent: NSObject {

    @objc public private(set) var on: [Any]
    @objc public private(set) var off: [Any]

    @objc public init(on: [Any]?, off: [Any]?) {
        self.on = on ?? []
        self.off = off ?? []
        super.init()
    }

    @objc public func toDictionary() -> [String: Any] {
        var onDictionaries: [Any] = []
        for geofence in on {
            if let g = geofence as? TSGeofence {
                onDictionaries.append(g.toDictionary())
            }
        }
        return [
            "on": onDictionaries,
            "off": off
        ]
    }
}
