import Foundation
import CoreLocation
import UIKit

#if canImport(ActivityKit)
import ActivityKit
#endif

@objc public final class TSLiveActivityManager: NSObject {
    private static let tokenDefaultsKey = "TSLocationManager_liveActivityPushToken"
    private static let idDefaultsKey = "TSLocationManager_liveActivityId"
    private static let trackingIdDefaultsKey = "TSLocationManager_liveActivityTrackingId"

    @objc public static let shared = TSLiveActivityManager()

    private let stateQueue = DispatchQueue(label: "TSLiveActivityManager.state")
    private var lastUpdateAt: Date = .distantPast
    private var locationCount = 0
    private var pushTokenTask: Task<Void, Never>?
    private var pendingStartIsMoving: Bool?
    private var lastError: String?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc public var pushToken: String? {
        UserDefaults.standard.string(forKey: Self.tokenDefaultsKey)
    }

    @objc public var activityId: String? {
        UserDefaults.standard.string(forKey: Self.idDefaultsKey)
    }

    @objc public func startIfNeeded(isMoving: Bool) {
        guard TSConfig.sharedInstance().app.liveActivityEnabled else { return }
        guard UIApplication.shared.applicationState == .active else {
            pendingStartIsMoving = isMoving
            log("Live Activity waiting for the app to become active")
            return
        }

        if #available(iOS 16.2, *) {
            Task { @MainActor in
                await self.startOrRecover(isMoving: isMoving)
            }
        } else {
            lastError = "Live Activities require iOS 16.2 or later"
            log(lastError!)
        }
    }

    @objc private func applicationDidBecomeActive() {
        guard let isMoving = pendingStartIsMoving else { return }
        pendingStartIsMoving = nil
        startIfNeeded(isMoving: isMoving)
    }

    @objc public func update(
        location: CLLocation?,
        isMoving: Bool,
        activity: String,
        force: Bool
    ) {
        guard TSConfig.sharedInstance().app.liveActivityEnabled else { return }

        stateQueue.async {
            let minimumInterval = max(5, TSConfig.sharedInstance().app.liveActivityUpdateInterval)
            guard force || Date().timeIntervalSince(self.lastUpdateAt) >= minimumInterval else { return }
            self.lastUpdateAt = Date()
            if location != nil {
                self.locationCount += 1
            }
            let count = self.locationCount

            if #available(iOS 16.2, *) {
                Task { @MainActor in
                    await self.updateActivities(
                        location: location,
                        isMoving: isMoving,
                        activity: activity,
                        locationCount: count
                    )
                }
            }
        }
    }

    @objc public func end() {
        pushTokenTask?.cancel()
        pushTokenTask = nil

        if #available(iOS 16.2, *) {
            Task { @MainActor in
                let final = self.makeState(
                    location: TSTrackingService.sharedInstance().lastGoodLocation,
                    isMoving: false,
                    activity: "stopped",
                    locationCount: self.locationCount,
                    status: "Tracking stopped"
                )
                let content = ActivityContent(
                    state: final,
                    staleDate: nil,
                    relevanceScore: 0
                )
                for activity in Activity<TSLiveTrackingAttributes>.activities {
                    await activity.end(content, dismissalPolicy: .immediate)
                }
                self.clearStoredActivity()
            }
        } else {
            clearStoredActivity()
        }
    }

    @objc public func stateDictionary() -> [String: Any] {
        let activitiesEnabled: Bool = {
            if #available(iOS 16.2, *) {
                return ActivityAuthorizationInfo().areActivitiesEnabled
            }
            return false
        }()
        let active: Bool = {
            if #available(iOS 16.2, *) {
                return !Activity<TSLiveTrackingAttributes>.activities.isEmpty
            }
            return false
        }()
        var state: [String: Any] = [
            "supported": {
                if #available(iOS 16.2, *) { return true }
                return false
            }(),
            "enabled": TSConfig.sharedInstance().app.liveActivityEnabled,
            "activitiesEnabled": activitiesEnabled,
            "active": active,
            "pushUpdates": TSConfig.sharedInstance().app.liveActivityPushUpdates
        ]
        if let activityId {
            state["activityId"] = activityId
        }
        if let pushToken {
            state["pushToken"] = pushToken
        }
        if let lastError {
            state["error"] = lastError
        }
        return state
    }

    @available(iOS 16.2, *)
    @MainActor
    private func startOrRecover(isMoving: Bool) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "Live Activities are disabled in iOS Settings"
            log(lastError!)
            return
        }

        if let activity = Activity<TSLiveTrackingAttributes>.activities.first {
            lastError = nil
            persist(activity: activity)
            observePushToken(for: activity)
            log("Recovered Live Activity \(activity.id)")
            await updateActivities(
                location: TSTrackingService.sharedInstance().lastGoodLocation,
                isMoving: isMoving,
                activity: TSTrackingService.sharedInstance().currentMotionActivity?.type ?? "unknown",
                locationCount: locationCount
            )
            return
        }

        let config = TSConfig.sharedInstance().app
        let trackingId = UserDefaults.standard.string(forKey: Self.trackingIdDefaultsKey)
            ?? UUID().uuidString
        let attributes = TSLiveTrackingAttributes(
            trackingId: trackingId,
            title: config.liveActivityTitle,
            subtitle: config.liveActivitySubtitle
        )
        let initial = makeState(
            location: TSTrackingService.sharedInstance().lastGoodLocation,
            isMoving: isMoving,
            activity: TSTrackingService.sharedInstance().currentMotionActivity?.type ?? "unknown",
            locationCount: locationCount
        )
        let staleDate = Date().addingTimeInterval(max(60, config.liveActivityStaleSeconds))
        let content = ActivityContent(state: initial, staleDate: staleDate, relevanceScore: 100)

        do {
            let pushType: PushType? = config.liveActivityPushUpdates ? .token : nil
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: pushType
            )
            lastError = nil
            UserDefaults.standard.set(trackingId, forKey: Self.trackingIdDefaultsKey)
            persist(activity: activity)
            observePushToken(for: activity)
            log("Started Live Activity \(activity.id), pushUpdates=\(config.liveActivityPushUpdates)")
        } catch {
            let firstError = error.localizedDescription
            guard config.liveActivityPushUpdates else {
                lastError = firstError
                log("Unable to start Live Activity: \(firstError)")
                return
            }

            // A push-enabled request requires the Push Notifications capability.
            // Keep local tracking useful when the host app has not configured it.
            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                lastError = nil
                UserDefaults.standard.set(trackingId, forKey: Self.trackingIdDefaultsKey)
                persist(activity: activity)
                log("Started local Live Activity after push request failed: \(firstError)")
            } catch {
                lastError = error.localizedDescription
                log("Unable to start local Live Activity: \(error.localizedDescription)")
            }
        }
    }

    @available(iOS 16.2, *)
    @MainActor
    private func updateActivities(
        location: CLLocation?,
        isMoving: Bool,
        activity: String,
        locationCount: Int
    ) async {
        let activities = Activity<TSLiveTrackingAttributes>.activities
        if activities.isEmpty {
            if UIApplication.shared.applicationState == .active {
                await startOrRecover(isMoving: isMoving)
            }
            return
        }

        let state = makeState(
            location: location,
            isMoving: isMoving,
            activity: activity,
            locationCount: locationCount
        )
        let config = TSConfig.sharedInstance().app
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(max(60, config.liveActivityStaleSeconds)),
            relevanceScore: isMoving ? 100 : 70
        )

        for liveActivity in activities {
            persist(activity: liveActivity)
            await liveActivity.update(content)
        }
    }

    @available(iOS 16.2, *)
    private func makeState(
        location: CLLocation?,
        isMoving: Bool,
        activity: String,
        locationCount: Int,
        status: String? = nil
    ) -> TSLiveTrackingAttributes.ContentState {
        TSLiveTrackingAttributes.ContentState(
            status: status ?? (isMoving ? "Live tracking" : "Stationary"),
            isMoving: isMoving,
            activity: activity.replacingOccurrences(of: "_", with: " "),
            latitude: location?.coordinate.latitude ?? 0,
            longitude: location?.coordinate.longitude ?? 0,
            accuracy: max(0, location?.horizontalAccuracy ?? 0),
            speed: max(0, location?.speed ?? 0),
            distance: TSOdometer.sharedInstance().getOdometer(),
            locationCount: locationCount,
            updatedAt: location?.timestamp ?? Date()
        )
    }

    @available(iOS 16.2, *)
    private func persist(activity: Activity<TSLiveTrackingAttributes>) {
        UserDefaults.standard.set(activity.id, forKey: Self.idDefaultsKey)
    }

    @available(iOS 16.2, *)
    private func observePushToken(for activity: Activity<TSLiveTrackingAttributes>) {
        guard TSConfig.sharedInstance().app.liveActivityPushUpdates else { return }
        pushTokenTask?.cancel()
        pushTokenTask = Task {
            for await tokenData in activity.pushTokenUpdates {
                guard !Task.isCancelled else { return }
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                UserDefaults.standard.set(token, forKey: Self.tokenDefaultsKey)
                TSLog.sharedInstance().notify("Live Activity push token: \(token)", debug: true)
            }
        }
    }

    private func clearStoredActivity() {
        UserDefaults.standard.removeObject(forKey: Self.idDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.trackingIdDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.tokenDefaultsKey)
        stateQueue.async {
            self.locationCount = 0
            self.lastUpdateAt = .distantPast
        }
    }

    private func log(_ message: String) {
        NSLog("[BGGEO][LiveActivity] \(message)")
        TSLog.sharedInstance().notify(message, debug: true)
    }
}
