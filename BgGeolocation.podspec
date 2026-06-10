require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "BgGeolocation"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/zohaibnaseer/react-native-bg-geolocation.git", :tag => "#{s.version}" }

  # ObjC++ TurboModule wrapper + all Swift engine files.
  # No binary dependency — the engine is compiled from Swift source directly.
  # The location-push extension's principal class (TSLocationPushService.swift)
  # is intentionally EXCLUDED from the pod — it belongs only to the
  # CLLocationPushServiceExtension target. Only the shared constants
  # (TSLocationPushShared.swift) are compiled into the engine so it can write
  # config into the App Group.
  # The location-push extension's PRINCIPAL class (TSLocationPushService.swift)
  # is excluded from the pod — it belongs only to the
  # CLLocationPushServiceExtension target. The shared constants, socket client,
  # and deliverer ARE compiled into the engine so the in-app background-push
  # handler can deliver natively without React Native.
  s.source_files = "ios/**/*.{h,m,mm,cpp}", "ios/engine/**/*.swift", "ios/liveactivity/**/*.swift", "ios/locationpush/TSLocationPushShared.swift", "ios/locationpush/TSLocationPushSocketClient.swift", "ios/locationpush/TSLocationPushDeliverer.swift"

  s.libraries    = 'sqlite3', 'z', 'stdc++'
  s.frameworks   = "CoreLocation", "CoreMotion", "AVFoundation", "AudioToolbox", "MediaPlayer", "UIKit", "CoreData",
                   "MessageUI", "UserNotifications", "BackgroundTasks", "ActivityKit"

  install_modules_dependencies(s)
end
