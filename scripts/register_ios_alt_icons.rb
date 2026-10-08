# 把 tool/gen_icons.dart 生成到 ios/Runner/ 的备用图标 PNG 注册进
# Runner 目标的 Copy Bundle Resources（否则 CI 用 flutter create 重建 iOS
# 工程后，这些松散文件不会被拷贝进 .app，CFBundleAlternateIcons 找不到图标，
# 运行时切换失效）。
#
# 依赖 xcodeproj gem（macOS runner 随 CocoaPods 提供）。
# 运行：ruby scripts/register_ios_alt_icons.rb
require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'Runner' }
raise '未找到 Runner target' if target.nil?

# Runner group（regenerated 工程里 path = 'Runner'）。
group = project.main_group.find_subpath('Runner', true)
raise '未找到 Runner group' if group.nil?

resources_phase = target.resources_build_phase

added = 0
Dir.glob('ios/Runner/*.png').sort.each do |path|
  name = File.basename(path)
  next if name.start_with?('LaunchImage')

  ref = group.files.find { |f| f.path == name } || group.new_reference(name)
  already = resources_phase.files_references.include?(ref)
  next if already

  resources_phase.add_file_reference(ref)
  added += 1
  puts "已注册资源: #{name}"
end

project.save
puts "iOS 备用图标注册完成，新增 #{added} 项。"
