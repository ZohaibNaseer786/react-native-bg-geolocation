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

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    if launchOptions?[.location] != nil || application.applicationState == .background {
      UserDefaults.standard.set(true, forKey: "TSLocationManager_didLaunchInBackground")
      UserDefaults.standard.synchronize()
    }

    // Register for server-triggered location pushes (kill-state tracking).
    if #available(iOS 15.0, *) {
      registerForLocationPushes()
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
      UserDefaults.standard.set(token, forKey: "TSLocationManager_locationPushToken")
      // Shared suite — available to the extension if needed.
      UserDefaults(suiteName: "group.com.masjidpilot.staging")?
        .set(token, forKey: "TSLocationManager_locationPushToken")
    }
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
