# Adds photo notifications to the Capacitor iPhone project. Run after add_widget.rb:
#   ruby scripts/add_notify.rb
# 1. A Notification Service Extension (HielloNotify) that puts the photo inside each notification.
# 2. Two small AppDelegate additions so the app can hand Apple's device token to the push plugin.
# Expects ios/App/HielloNotify/NotificationService.swift and Info.plist copied in by codemagic.yaml.
require 'xcodeproj'

NAME = 'HielloNotify'
BUNDLE = 'com.hiello.family.notify'

# ---------- AppDelegate: pass the notification token to Capacitor ----------
ad_path = File.expand_path('ios/App/App/AppDelegate.swift', Dir.pwd)
ad = File.read(ad_path)
unless ad.include?('capacitorDidRegisterForRemoteNotifications')
  hook = <<~SWIFT

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications, object: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
    }
  SWIFT
  idx = ad.rindex('}') or abort('add_notify: AppDelegate.swift looks wrong')
  ad = ad[0...idx] + hook.gsub(/^/, '    ') + "}\n"
  File.write(ad_path, ad)
  puts 'add_notify: AppDelegate now forwards the notification token'
end

# ---------- the Notification Service Extension ----------
proj_path = File.expand_path('ios/App/App.xcodeproj', Dir.pwd)
project = Xcodeproj::Project.open(proj_path)
app = project.targets.find { |t| t.name == 'App' } or abort('add_notify: App target not found')
if project.targets.any? { |t| t.name == NAME }
  puts 'add_notify: already added'
  exit 0
end

app_cfg = app.build_configurations.first.build_settings
marketing = app_cfg['MARKETING_VERSION'] || '1.0'
build_no = app_cfg['CURRENT_PROJECT_VERSION'] || '1'
team = app_cfg['DEVELOPMENT_TEAM']

ext = project.new_target(:app_extension, NAME, :ios, '15.0', project.products_group, :swift)
group = project.main_group.new_group(NAME, NAME)
ext.add_file_references([group.new_reference('NotificationService.swift')])
group.new_reference('Info.plist')
ext.add_system_framework(%w[UserNotifications])

ext.build_configurations.each do |c|
  bs = c.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE
  bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
  bs['INFOPLIST_FILE'] = "#{NAME}/Info.plist"
  bs['GENERATE_INFOPLIST_FILE'] = 'NO'
  bs['SWIFT_VERSION'] = '5.0'
  bs['TARGETED_DEVICE_FAMILY'] = '1'
  bs['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  bs['MARKETING_VERSION'] = marketing
  bs['CURRENT_PROJECT_VERSION'] = build_no
  bs['SKIP_INSTALL'] = 'YES'
  bs['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  bs['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  bs['DEVELOPMENT_TEAM'] = team if team
end

embed = app.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' } ||
        app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(ext.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeaderOnCopy'] }
app.add_dependency(ext)

phases = app.build_phases
res_idx = phases.index(app.resources_build_phase)
if res_idx
  phases.delete(embed)
  phases.insert(res_idx + 1, embed)
end

project.save
puts "add_notify: added #{NAME} (#{BUNDLE}, iOS 15+)"
puts 'add_notify: targets now: ' + project.targets.map(&:name).join(', ')
