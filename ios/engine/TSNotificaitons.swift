import Foundation
import UserNotifications

@objc public final class TSNotifications: NSObject {

    @objc public var prepared: Bool = false

    @objc public static let shared = TSNotifications()

    @objc public func prepareIfNeeded(_ context: Any?) {
        guard !prepared else { return }
        prepared = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.getNotificationSettings { settings in
            if settings.authorizationStatus != .notDetermined {
                NSLog("[TS] notif status=%ld", settings.authorizationStatus.rawValue)
            } else {
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    NSLog("[TS] notif auth: granted=%d err=%@", granted, error?.localizedDescription ?? "")
                }
            }
        }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([.alert, .badge, .sound])
        }
    }
}

extension TSNotifications: UNUserNotificationCenterDelegate {}
