import Foundation
import CoreLocation

@objc public class BGPolygonStreamRequest: NSObject {

    @objc public var identifier: String
    @objc public var vertices: [[CLLocationDegrees]]
    @objc public var interval: Double
    @objc public var success: ((Any?) -> Void)?
    @objc public var failure: ((Int) -> Void)?

    @objc public init(
        identifier: String,
        vertices: [[CLLocationDegrees]],
        interval: Double,
        success: @escaping (Any?) -> Void,
        failure: @escaping (Int) -> Void
    ) {
        self.identifier = identifier
        self.vertices = vertices
        self.interval = interval
        self.success = success
        self.failure = failure
        super.init()
    }

    @objc public override init() {
        identifier = UUID().uuidString
        vertices = []
        interval = 1000
        super.init()
    }

    @objc public func containsCoordinate(_ coord: CLLocationCoordinate2D) -> Bool {
        guard vertices.count >= 3 else { return false }
        var inside = false
        var j = vertices.count - 1
        for i in 0..<vertices.count {
            let xi = vertices[i][0], yi = vertices[i][1]
            let xj = vertices[j][0], yj = vertices[j][1]
            let intersect = ((yi > coord.latitude) != (yj > coord.latitude)) &&
                (coord.longitude < (xj - xi) * (coord.latitude - yi) / (yj - yi) + xi)
            if intersect { inside = !inside }
            j = i
        }
        return inside
    }
}
