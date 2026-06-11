require "xcodeproj"

project_path = File.join(__dir__, "BgGeolocationExample.xcodeproj")
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |target| target.name == "BgGeolocationExample" }
abort "BgGeolocationExample target not found" unless app_target

extension_target = project.targets.find { |target| target.name == "BgGeolocationLiveActivity" }
unless extension_target
  extension_target = project.new_target(
    :app_extension,
    "BgGeolocationLiveActivity",
    :ios,
    "16.2"
  )
end

extension_group = project.main_group.find_subpath("BgGeolocationLiveActivity", true)
extension_group.set_source_tree("<group>")
extension_group.set_path("BgGeolocationLiveActivity")

source_paths = [
  "BgGeolocationLiveActivityBundle.swift",
  "LiveTrackingWidget.swift"
]

source_paths.each do |path|
  file = extension_group.files.find { |item| item.path == path } || extension_group.new_file(path)
  unless extension_target.source_build_phase.files_references.include?(file)
    extension_target.source_build_phase.add_file_reference(file)
  end
end

shared_group = project.main_group.find_subpath("LiveActivityShared", true)
shared_group.set_source_tree("SOURCE_ROOT")
shared_group.set_path("../../ios/liveactivity")
attributes_file = shared_group.files.find { |item| item.path == "BGLiveTrackingAttributes.swift" } ||
  shared_group.new_file("BGLiveTrackingAttributes.swift")
unless extension_target.source_build_phase.files_references.include?(attributes_file)
  extension_target.source_build_phase.add_file_reference(attributes_file)
end

%w[ActivityKit.framework SwiftUI.framework WidgetKit.framework].each do |framework_name|
  framework = project.frameworks_group.files.find { |item| item.path == "System/Library/Frameworks/#{framework_name}" } ||
    project.frameworks_group.new_file("System/Library/Frameworks/#{framework_name}")
  framework.source_tree = "SDKROOT"
  unless extension_target.frameworks_build_phase.files_references.include?(framework)
    extension_target.frameworks_build_phase.add_file_reference(framework)
  end
end

extension_target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["APPLICATION_EXTENSION_API_ONLY"] = "YES"
  settings["CODE_SIGN_STYLE"] = "Automatic"
  settings["CURRENT_PROJECT_VERSION"] = "1"
  settings["DEVELOPMENT_TEAM"] = "KVJ86QZYD3"
  settings["GENERATE_INFOPLIST_FILE"] = "NO"
  settings["INFOPLIST_FILE"] = "BgGeolocationLiveActivity/Info.plist"
  settings["IPHONEOS_DEPLOYMENT_TARGET"] = "16.2"
  settings["LD_RUNPATH_SEARCH_PATHS"] = [
    "$(inherited)",
    "@executable_path/Frameworks",
    "@executable_path/../../Frameworks"
  ]
  settings["MARKETING_VERSION"] = "1.0"
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.masjidpilot.staging.LiveActivity"
  settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  settings["SKIP_INSTALL"] = "YES"
  settings["SUPPORTED_PLATFORMS"] = "iphoneos iphonesimulator"
  settings["SWIFT_VERSION"] = "5.0"
  settings["TARGETED_DEVICE_FAMILY"] = "1,2"
end

unless app_target.dependencies.any? { |dependency| dependency.target == extension_target }
  app_target.add_dependency(extension_target)
end

embed_phase = app_target.copy_files_build_phases.find { |phase| phase.name == "Embed App Extensions" } ||
  app_target.new_copy_files_build_phase("Embed App Extensions")
embed_phase.dst_subfolder_spec = "13"

unless embed_phase.files_references.include?(extension_target.product_reference)
  build_file = embed_phase.add_file_reference(extension_target.product_reference)
  build_file.settings = {
    "ATTRIBUTES" => ["CodeSignOnCopy", "RemoveHeadersOnCopy"]
  }
end

project.save
