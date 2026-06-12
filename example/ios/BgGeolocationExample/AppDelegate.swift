import UIKit
import CoreLocation
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  var reactNativeDelegate: ReactNativeDelegate?
  var reactNativeFactory: RCTReactNativeFactory?

  // Strong ref required — CLLocationManager is deallocated (and the push
  // registration aborted) if we let it go out of scope before the callback.
  private var locationPushManager: CLLocationManager?

  // Background-push completion handlers, keyed by a per-push requestId. JS calls
  // BackgroundGeolocation.finishLocationPush(requestId) when it's done, which
  // posts BGLocationPushFinished → we invoke + remove the matching handler.
  private var backgroundPushCompletions: [String: (UIBackgroundFetchResult) -> Void] = [:]

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    if launchOptions?[.location] != nil || application.applicationState == .background {
      UserDefaults.standard.set(true, forKey: "BGLocationManager_didLaunchInBackground")
      UserDefaults.standard.synchronize()
    }

    // Register for server-triggered location pushes (kill-state tracking).
    if #available(iOS 15.0, *) {
      registerForLocationPushes()
    }

    // Register for standard remote notifications (app-alive background pushes:
    // apns-push-type=background, content-available=1).
    application.registerForRemoteNotifications()

    // When JS signals it finished handling a background push, release the app.
    NotificationCenter.default.addObserver(
      forName: Notification.Name("BGLocationPushFinished"),
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let requestId = note.userInfo?["requestId"] as? String else { return }
      self?.completeBackgroundPush(requestId: requestId, result: .newData)
    }

    let delegate = ReactNativeDelegate()
    let factory  = RCTReactNativeFactory(delegate: delegate)
    delegate.dependencyProvider = RCTAppDependencyProvider()

    reactNativeDelegate = delegate
    reactNativeFactory  = factory

    window = UIWindow(frame: UIScreen.main.bounds)

    factory.startReactNative(
      withModuleName: "BgGeolocationExample",
      in: window,
      launchOptions: launchOptions
    )

    return true
  }

  // MARK: - Location Push registration

  // Obtains the device's location-push APNs token. iOS delivers pushes sent to
  // this token to the Location Push Service Extension — even when the app is
  // force-quit. Ship the token to your server so it can trigger location fetches.
  @available(iOS 15.0, *)
  private func registerForLocationPushes() {
    let manager = CLLocationManager()
    locationPushManager = manager
    manager.startMonitoringLocationPushes { [weak self] tokenData, error in
      defer { self?.locationPushManager = nil }
      if let error = error {
        NSLog("[BGGEO] Location push registration FAILED: \(error.localizedDescription)")
        return
      }
      guard let tokenData = tokenData else {
        NSLog("[BGGEO] Location push registration returned no token")
        return
      }
      let token = tokenData.map { String(format: "%02hhx", $0) }.joined()
      NSLog("[BGGEO] ✅ Location push token: \(token)")

      // Standard suite — JS reads via BackgroundGeolocation.getLocationPushToken().
      UserDefaults.standard.set(token, forKey: "BGLocationManager_locationPushToken")
      // Shared suite — available to the extension if needed.
      if let appGroup = Bundle.main.object(
        forInfoDictionaryKey: "BGLocationPushAppGroupIdentifier"
      ) as? String {
        UserDefaults(suiteName: appGroup)?
          .set(token, forKey: "BGLocationManager_locationPushToken")
      }
    }
  }

  // MARK: - Standard remote-notification token (background pushes)

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02hhx", $0) }.joined()
    NSLog("[BGGEO] ✅ APNs device token: \(token)")
    UserDefaults.standard.set(token, forKey: "BGLocationManager_apnsDeviceToken")
    // The JS layer ships this to the server (see registerApnsDeviceToken()).
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("[BGGEO] APNs registration failed: \(error.localizedDescription)")
  }

  // MARK: - Background push → JS → socket

  // apns-push-type=background, content-available=1. Fires only while the app
  // process is alive (foreground or backgrounded-but-not-killed). We hand the
  // location-query id to JS, which fetches a location and emits it over the
  // socket, then calls finishLocationPush(requestId).
  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    let queryId = Self.extractLocationQueryId(userInfo)
    guard let queryId = queryId else {
      NSLog("[BGGEO] background push without location-query id — ignoring")
      completionHandler(.noData)
      return
    }

    let requestId = UUID().uuidString
    backgroundPushCompletions[requestId] = completionHandler
    NSLog("[BGGEO] background push → JS (requestId=\(requestId), query=\(queryId))")

    NotificationCenter.default.post(
      name: Notification.Name("BGLocationPushBackground"),
      object: nil,
      userInfo: ["requestId": requestId, "locationQueryId": queryId]
    )

    // Safety net: iOS gives us ~30s. If JS never calls finishLocationPush,
    // release the app ourselves so we don't get killed for over-running.
    DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
      self?.completeBackgroundPush(requestId: requestId, result: .failed)
    }
  }

  private func completeBackgroundPush(requestId: String, result: UIBackgroundFetchResult) {
    guard let handler = backgroundPushCompletions.removeValue(forKey: requestId) else { return }
    NSLog("[BGGEO] completing background push requestId=\(requestId)")
    handler(result)
  }

  private static func extractLocationQueryId(_ userInfo: [AnyHashable: Any]) -> String? {
    let candidates = ["location-query", "locationQuery", "location_query",
                      "locationQueryId", "queryId", "query-id"]
    var scopes: [[AnyHashable: Any]] = [userInfo]
    if let aps = userInfo["aps"] as? [AnyHashable: Any] { scopes.append(aps) }
    for scope in scopes {
      for key in candidates {
        if let s = scope[key] as? String, !s.isEmpty { return s }
        if let n = scope[key] as? NSNumber { return n.stringValue }
      }
    }
    return nil
  }
}

class ReactNativeDelegate: RCTDefaultReactNativeFactoryDelegate {
  override func sourceURL(for bridge: RCTBridge) -> URL? {
    self.bundleURL()
  }

  override func bundleURL() -> URL? {
#if DEBUG
    if let metroURL = RCTBundleURLProvider.sharedSettings().jsBundleURL(forBundleRoot: "index") {
      return metroURL
    }

#if targetEnvironment(simulator)
    return URL(string: "http://localhost:8081/index.bundle?platform=ios&dev=true&minify=false")
#else
    return Bundle.main.url(forResource: "main", withExtension: "jsbundle")
#endif
#else
    return Bundle.main.url(forResource: "main", withExtension: "jsbundle")
#endif
  }
}
