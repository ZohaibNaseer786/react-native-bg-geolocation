import ActivityKit
import Foundation

@available(iOS 16.2, *)
public struct BGLiveTrackingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var status: String
        public var isMoving: Bool
        public var activity: String
        public var latitude: Double
        public var longitude: Double
        public var accuracy: Double
        public var speed: Double
        public var distance: Double
        public var locationCount: Int
        public var updatedAt: Date

        public init(
            status: String,
            isMoving: Bool,
            activity: String,
            latitude: Double,
            longitude: Double,
            accuracy: Double,
            speed: Double,
            distance: Double,
            locationCount: Int,
            updatedAt: Date
        ) {
            self.status = status
            self.isMoving = isMoving
            self.activity = activity
            self.latitude = latitude
            self.longitude = longitude
            self.accuracy = accuracy
            self.speed = speed
            self.distance = distance
            self.locationCount = locationCount
            self.updatedAt = updatedAt
        }
    }

    public var trackingId: String
    public var title: String
    public var subtitle: String

    public init(trackingId: String, title: String, subtitle: String) {
        self.trackingId = trackingId
        self.title = title
        self.subtitle = subtitle
    }
}
