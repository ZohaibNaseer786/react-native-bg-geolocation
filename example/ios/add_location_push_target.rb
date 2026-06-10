require "xcodeproj"

# Adds the iOS Location Push Service Extension target to the example project,
# wires its sources/frameworks/Info.plist/entitlements, and attaches the host
# app's entitlements (location.push + App Group + aps-environment).
#
# Idempotent: safe to run multiple times. Run with a UTF-8 locale:
#   LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 ruby add_location_push_target.rb

APP_TARGET_NAME       = "BgGeolocationExample"
EXT_TARGET_NAME       = "LocationPushExtension"
EXT_BUNDLE_ID         = "com.masjidpilot.staging.location-push"
APP_GROUP             = "group.com.masjidpilot.staging"
TEAM_ID               = "KVJ86QZYD3"
APP_ENTITLEMENTS_PATH = "BgGeolocationExample/BgGeolocationExample.entitlements"
EXT_ENTITLEMENTS_PATH = "LocationPushExtension/LocationPushExtension.entitlements"
EXT_INFO_PLIST        = "LocationPushExtension/Info.plist"

project_path = File.join(__dir__, "#{APP_TARGET_NAME}.xcodeproj")
project = Xcodeproj::Project.open(project_path)

app_target = project.targets.find { |t| t.name == APP_TARGET_NAME }
abort "#{APP_TARGET_NAME} target not found" unless app_target

# ── 1. Create (or find) the extension target ────────────────────────────────
ext_target = project.targets.find { |t| t.name == EXT_TARGET_NAME }
unless ext_target
  ext_target = project.new_target(:app_extension, EXT_TARGET_NAME, :ios, "15.0")
end

# ── 2. Source files ─────────────────────────────────────────────────────────
# The extension's principal class + shared constants live in the PACKAGE, so the
# library stays the single source of truth. Reference them in via a group whose
# path points at ../../ios/locationpush.
shared_group = project.main_group.find_subpath("LocationPushShared", true)
shared_group.set_source_tree("SOURCE_ROOT")
shared_group.set_path("../../ios/locationpush")

%w[TSLocationPushShared.swift TSLocationPushSocketClient.swift TSLocationPushDeliverer.swift TSLocationPushService.swift].each do |name|
  file = shared_group.files.find { |f| f.path == name } || shared_group.new_file(name)
  unless ext_target.source_build_phase.files_references.include?(file)
    ext_target.source_build_phase.add_file_reference(file)
  end
end

# ── 3. Info.plist + entitlements file references (so they show in the project) ─
ext_group = project.main_group.find_subpath(EXT_TARGET_NAME, true)
ext_group.set_source_tree("<group>")
ext_group.set_path(EXT_TARGET_NAME)
%w[Info.plist LocationPushExtension.entitlements].each do |name|
  ext_group.files.find { |f| f.path == name } || ext_group.new_file(name)
end

# ── 4. Frameworks ─────────────────────────────────────────────────────────
%w[CoreLocation.framework].each do |framework_name|
  framework = project.frameworks_group.files.find { |f| f.path == "System/Library/Frameworks/#{framework_name}" } ||
    project.frameworks_group.new_file("System/Library/Frameworks/#{framework_name}")
  framework.source_tree = "SDKROOT"
  unless ext_target.frameworks_build_phase.files_references.include?(framework)
    ext_target.frameworks_build_phase.add_file_reference(framework)
  end
end

# ── 5. Build settings for the extension ─────────────────────────────────────
ext_target.build_configurations.each do |config|
  s = config.build_settings
  s["APPLICATION_EXTENSION_API_ONLY"] = "YES"
  s["CODE_SIGN_STYLE"] = "Automatic"
  s["CODE_SIGN_ENTITLEMENTS"] = EXT_ENTITLEMENTS_PATH
  s["CURRENT_PROJECT_VERSION"] = "1"
  s["DEVELOPMENT_TEAM"] = TEAM_ID
  s["GENERATE_INFOPLIST_FILE"] = "NO"
  s["INFOPLIST_FILE"] = EXT_INFO_PLIST
  s["IPHONEOS_DEPLOYMENT_TARGET"] = "15.0"
  s["LD_RUNPATH_SEARCH_PATHS"] = [
    "$(inherited)",
    "@executable_path/Frameworks",
    "@executable_path/../../Frameworks"
  ]
  s["MARKETING_VERSION"] = "1.0"
  s["PRODUCT_BUNDLE_IDENTIFIER"] = EXT_BUNDLE_ID
  s["PRODUCT_NAME"] = "$(TARGET_NAME)"
  s["SKIP_INSTALL"] = "YES"
  s["SUPPORTED_PLATFORMS"] = "iphoneos iphonesimulator"
  s["SWIFT_VERSION"] = "5.0"
  s["TARGETED_DEVICE_FAMILY"] = "1,2"
end

# ── 6. Attach the host app entitlements (location.push + App Group + aps) ────
app_target.build_configurations.each do |config|
  config.build_settings["CODE_SIGN_ENTITLEMENTS"] = APP_ENTITLEMENTS_PATH
end

# ── 7. Dependency + embed the extension into the app ────────────────────────
unless app_target.dependencies.any? { |d| d.target == ext_target }
  app_target.add_dependency(ext_target)
end

embed_phase = app_target.copy_files_build_phases.find { |p| p.name == "Embed App Extensions" } ||
  app_target.new_copy_files_build_phase("Embed App Extensions")
embed_phase.dst_subfolder_spec = "13" # PlugIns

unless embed_phase.files_references.include?(ext_target.product_reference)
  build_file = embed_phase.add_file_reference(ext_target.product_reference)
  build_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
end

project.save
puts "✅ Added #{EXT_TARGET_NAME} target (bundle id #{EXT_BUNDLE_ID})"
puts "   App Group: #{APP_GROUP}"
puts "   Remember: the com.apple.developer.location.push entitlement requires Apple approval."
