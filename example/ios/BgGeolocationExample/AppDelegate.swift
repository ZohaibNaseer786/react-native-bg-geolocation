import UIKit
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  var reactNativeDelegate: ReactNativeDelegate?
  var reactNativeFactory: RCTReactNativeFactory?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    // NOTE: TSLocationManager manages its own background lifecycle — significant
    // location changes, CLVisit monitoring, geofence wakeups and the headless
    // JS launch are all handled inside the engine. We only need the standard
    // React Native bootstrap here; the engine re-arms itself on a kill-state
    // relaunch via the UIApplicationLaunchOptionsLocationKey it inspects.
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
    return Self.metroURLFromBundledIP()
      ?? Bundle.main.url(forResource: "main", withExtension: "jsbundle")
#endif
#else
    return Bundle.main.url(forResource: "main", withExtension: "jsbundle")
#endif
  }

  private static func metroURLFromBundledIP() -> URL? {
    guard let path = Bundle.main.path(forResource: "ip", ofType: "txt"),
          let contents = try? String(contentsOfFile: path, encoding: .utf8)
    else {
      return nil
    }

    let host = contents.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty else {
      return nil
    }

    return URL(string: "http://\(host):8081/index.bundle?platform=ios&dev=true&minify=false")
  }
}
