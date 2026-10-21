# 配置 iOS 备用图标（Asset Catalog appiconset 方案）。
#
# 背景：iOS CI 每个平台 job 都会 rm -rf ios 再用 flutter create 重建工程，
# 模板的 project.pbxproj 没有备用图标所需设置。备用图标改为 Asset Catalog
# appiconset 后，必须打开 "Include All App Icon Assets"（否则除主
# ASSETCATALOG_COMPILER_APPICON_NAME 外的 appiconset 不会编进 Assets.car，
# setAlternateIconName 找不到图标 → OSStatus -54）。
#
# 同时声明 Alternate App Icon Sets：这是 Apple 文档推荐的备用图标声明方式，
# Xcode 会据此生成 CFBundleAlternateIcons（与手写 Info.plist 互为兜底）。
# iOS 26 的 Liquid Glass 图标堆栈从各 appiconset 的 1024 营销图标生成，
# tool/gen_icons.dart 已为每个备用集补齐完整尺寸。
#
# 依赖 xcodeproj gem（macOS runner 随 CocoaPods 提供）。
# 运行：ruby scripts/configure_ios_icons.rb
require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'Runner' }
raise '未找到 Runner target' if target.nil?

ALTERNATES = 'artistic mint glass'.freeze

changed = 0
target.build_configurations.each do |config|
  settings = config.build_settings
  if settings['ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS'] != 'YES'
    settings['ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS'] = 'YES'
    changed += 1
  end
  if settings['ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES'] != ALTERNATES
    settings['ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES'] = ALTERNATES
    changed += 1
  end
end

project.save
puts "iOS 图标构建设置更新完成：Include All = YES，" \
     "Alternate App Icon Sets = #{ALTERNATES}（#{changed} 项变更）。"
