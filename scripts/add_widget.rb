# Adds the Hiello home screen widget (a WidgetKit extension) to the Capacitor iPhone project.
# Runs on Codemagic after `npx cap add ios` (the ios/ folder is generated fresh each build).
#   ruby scripts/add_widget.rb
# Expects these files already copied in by codemagic.yaml:
#   ios/App/App/HielloWidgetPlugin.swift, HielloViewController.swift, App.entitlements
#   ios/App/HielloWidget/HielloWidget.swift, Info.plist, HielloWidget.entitlements, PrivacyInfo.xcprivacy
require 'xcodeproj'

APP_GROUP_ID = 'group.com.hiello.family'
WIDGET_BUNDLE = 'com.hiello.family.widget'
WIDGET_NAME = 'HielloWidget'

proj_path = File.expand_path('ios/App/App.xcodeproj', Dir.pwd)
project = Xcodeproj::Project.open(proj_path)
app = project.targets.find { |t| t.name == 'App' } or abort('add_widget: App target not found')

if project.targets.any? { |t| t.name == WIDGET_NAME }
  puts 'add_widget: widget already added, nothing to do'
  exit 0
end

app_cfg = app.build_configurations.first.build_settings
marketing = app_cfg['MARKETING_VERSION'] || '1.0'
build_no = app_cfg['CURRENT_PROJECT_VERSION'] || '1'
team = app_cfg['DEVELOPMENT_TEAM']

# ---------- the widget extension target ----------
widget = project.new_target(:app_extension, WIDGET_NAME, :ios, '17.0', project.products_group, :swift)

wgroup = project.main_group.new_group(WIDGET_NAME, WIDGET_NAME)
widget.add_file_references([wgroup.new_reference('HielloWidget.swift')])
wgroup.new_reference('Info.plist')
wgroup.new_reference('HielloWidget.entitlements')
widget.resources_build_phase.add_file_reference(wgroup.new_reference('PrivacyInfo.xcprivacy'))
widget.add_system_framework(%w[WidgetKit SwiftUI AppIntents])

widget.build_configurations.each do |c|
  bs = c.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = WIDGET_BUNDLE
  bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
  bs['INFOPLIST_FILE'] = "#{WIDGET_NAME}/Info.plist"
  bs['GENERATE_INFOPLIST_FILE'] = 'NO'
  bs['CODE_SIGN_ENTITLEMENTS'] = "#{WIDGET_NAME}/HielloWidget.entitlements"
  bs['SWIFT_VERSION'] = '5.0'
  bs['TARGETED_DEVICE_FAMILY'] = '1'
  bs['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  bs['MARKETING_VERSION'] = marketing
  bs['CURRENT_PROJECT_VERSION'] = build_no
  bs['SKIP_INSTALL'] = 'YES'
  bs['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  bs['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  bs['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  bs['DEVELOPMENT_TEAM'] = team if team
end

# ---------- put the widget inside the app ----------
embed = app.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' } ||
        app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(widget.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeaderOnCopy'] }
app.add_dependency(widget)

# Keep the embed step right after Resources (before CocoaPods' script steps) to avoid Xcode's "Cycle inside App" error.
phases = app.build_phases
res_idx = phases.index(app.resources_build_phase)
if res_idx
  phases.delete(embed)
  phases.insert(res_idx + 1, embed)
end

# ---------- the app's side: the widget bridge, its screen, and the shared App Group ----------
agroup = project.main_group.children.find { |g| g.respond_to?(:path) && (g.path == 'App' || g.display_name == 'App') && g.is_a?(Xcodeproj::Project::Object::PBXGroup) } or abort('add_widget: App group not found')
%w[HielloWidgetPlugin.swift HielloViewController.swift].each do |f|
  next if agroup.files.any? { |x| x.path == f }
  app.add_file_references([agroup.new_reference(f)])
end
agroup.new_reference('App.entitlements') unless agroup.files.any? { |x| x.path == 'App.entitlements' }
app.build_configurations.each { |c| c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'App/App.entitlements' }

project.save
puts "add_widget: added #{WIDGET_NAME} (#{WIDGET_BUNDLE}, iOS 17+) to App, app group #{APP_GROUP_ID}"
puts 'add_widget: targets now: ' + project.targets.map(&:name).join(', ')
puts 'add_widget: App build phases: ' + app.build_phases.map(&:display_name).join(' > ')
