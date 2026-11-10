# Adds the free alternate app icons (Pink, Cream, Classic) to the iPhone app.
# Expects ios/App/App/IconPink@2x.png etc. (copied by codemagic.yaml) and registers them in Info.plist there.
require 'xcodeproj'
NAMES = %w[Pink Cream Classic]
project = Xcodeproj::Project.open(File.expand_path('ios/App/App.xcodeproj', Dir.pwd))
app = project.targets.find { |t| t.name == 'App' } or abort('add_icons: App target not found')
group = project.main_group.find_subpath('App', false) or abort('add_icons: App group not found')
NAMES.each do |n|
  %w[@2x @3x].each do |s|
    f = "Icon#{n}#{s}.png"
    next if group.files.any? { |r| r.path == f }
    ref = group.new_reference(f)
    app.resources_build_phase.add_file_reference(ref, true)
  end
end
project.save
puts 'add_icons: added ' + NAMES.join(', ')
