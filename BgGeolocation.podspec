require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))
react_native_package = Pod::Executable.execute_command(
  "node",
  [
    "-p",
    "require.resolve('react-native/package.json', { paths: [process.argv[1]] })",
    __dir__,
  ]
).strip
require File.join(File.dirname(react_native_package), "scripts/react_native_pods")

Pod::Spec.new do |s|
  s.name         = "BgGeolocation"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => "15.1" }
  s.source       = { :git => "https://github.com/ZohaibNaseer786/react-native-bg-geolocation.git", :tag => "#{s.version}" }

  # ObjC++ TurboModule wrapper + all Swift engine files.
  # No binary dependency — the engine is compiled from Swift source directly.
  # The location-push extension's PRINCIPAL class (BGLocationPushService.swift)
  # is excluded from the pod — it belongs only to the
  # CLLocationPushServiceExtension target. The shared constants, socket client,
  # and deliverer ARE compiled into the engine so the in-app background-push
  # handler can deliver natively without React Native.
  s.source_files = "ios/**/*.{h,m,mm,cpp}", "ios/engine/**/*.swift", "ios/liveactivity/**/*.swift", "ios/locationpush/BGLocationPushShared.swift", "ios/locationpush/BGLocationPushSocketClient.swift", "ios/locationpush/BGLocationPushDeliverer.swift"

  s.libraries    = 'sqlite3', 'z', 'stdc++'
  s.frameworks   = "CoreLocation", "CoreMotion", "AVFoundation", "AudioToolbox", "MediaPlayer", "UIKit", "CoreData",
                   "MessageUI", "UserNotifications", "BackgroundTasks", "ActivityKit"

  install_modules_dependencies(s)
end
