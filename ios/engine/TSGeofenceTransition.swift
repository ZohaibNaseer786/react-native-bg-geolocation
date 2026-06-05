import Foundation
import CoreLocation

@objc public final class TSGeofenceTransition: NSObject {

    @objc public var location: CLLocation?
    @objc public var triggerLocation: CLLocation?
    @objc public var triggerLocationRequest: TSCurrentPositionRequest?
    @objc public var loiteringRegion: CLCircularRegion?
    @objc public var isLoitering: Bool = false
    @objc public var didLoiter: Bool = false
    @objc public var didComplete: Bool = false
    @objc public var onComplete: ((NSError?) -> Void)?
    @objc public var geofence: TSGeofence?
    @objc public var region: CLRegion?
    @objc public var timestamp: Date?
    @objc public var action: String?

    @objc public init(geofence: TSGeofence?,
                       region: CLRegion?,
                       action: String?,
                       onComplete: ((NSError?) -> Void)?) {
        self.geofence = geofence
        self.region = region
        self.action = action
        self.onComplete = onComplete
        self.isLoitering = false
        self.didLoiter = false
        self.didComplete = false
        self.timestamp = Date()
        super.init()
        requestTriggerLocation()
    }

    @objc public convenience init(geofence: TSGeofence?,
                                  action: String?,
                                  onComplete: ((NSError?) -> Void)?) {
        self.init(geofence: geofence, region: nil, action: action, onComplete: onComplete)
    }

    @objc public convenience init(geofence: TSGeofence?,
                                  action: String?,
                                  triggerLocation: CLLocation?) {
        self.init(geofence: geofence, action: action, onComplete: nil)
        if let triggerLocation = triggerLocation {
            self.triggerLocation = triggerLocation
        }
    }

    @objc public func getLoiteringRegion(_ location: CLLocation) -> CLCircularRegion? {
        if let existing = loiteringRegion {
            return existing
        }
        guard let region = region as? CLCircularRegion else { return nil }
        let center = CLLocation(latitude: region.center.latitude,
                                longitude: region.center.longitude)
        let distance = location.distance(from: center)
        let accuracy = location.horizontalAccuracy
        let radius = distance + max(accuracy * 1.5, 10.0)
        let loitering = CLCircularRegion(center: region.center,
                                         radius: radius,
                                         identifier: "loitering-region")
        self.loiteringRegion = loitering
        return loitering
    }

    @objc public func requestTriggerLocation() {
        let label = String(format: "TSGeofenceTransition:%@:%@",
                           action ?? "", geofence?.identifier ?? "")
        weak var weakSelf = self
        let request = TSCurrentPositionRequest(
            type: "geofence",
            maximumAge: 30.0,
            timeout: 10000,
            desiredAccuracy: 1,
            allowStale: true,
            samples: 3,
            label: label,
            persist: true,
            extras: nil,
            success: { _ in },
            failure: { (code: Int) in
                guard let strongSelf = weakSelf else { return }
                let error = NSError(domain: "TSGeofenceTransition", code: code)
                strongSelf.onComplete?(error)
            })
        self.triggerLocationRequest = request
        TSLocationRequestService.sharedInstance().requestLocation(request)
    }

    @objc public func cancelLoitering() {
        guard let request = triggerLocationRequest else { return }
        TSLocationRequestService.sharedInstance().cancelRequest(request.label ?? "")
        TSLog.sharedInstance().notify("Geofence DWELL cancelled", debug: TSConfig.sharedInstance().logger.debug)
        triggerLocationRequest = nil
    }
}
