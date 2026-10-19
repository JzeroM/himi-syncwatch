// 从 assets/icon/<name>.png 生成运行时切换所需的备用图标资源：
// - Android 备用图标 mipmap-*/ic_launcher_<name>.png（48/72/96/144/192）
// - iOS 备用图标 Asset Catalog appiconset：
//   ios/Runner/Assets.xcassets/<name>.appiconset/（多尺寸 PNG + Contents.json）
// - 设置页预览 assets/icons/<name>.png (256)
//
// 默认图标（default，全平台：Android/iOS/Windows）由 flutter_launcher_icons
// 生成；本脚本只补「备用图标 + 预览」。
//
// iOS 采用 appiconset 而非散装 PNG + CFBundleIconFiles：新系统下散装备用
// 图标常不被 setAlternateIconName 识别（OSStatus -54），且 Info.plist 的
// CFBundleAlternateIcons 需配套改为 CFBundleIconName；另需 Xcode 构建设置
// ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES（否则非主
// appiconset 不会编进 Assets.car），见 scripts/configure_ios_icons.rb。
//
// 运行：dart run tool/gen_icons.dart
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

/// 默认图标（由 flutter_launcher_icons 处理，这里只出预览）。
const String defaultIcon = 'default';

/// 全部可选图标（含默认）。
const List<String> allIcons = ['default', 'artistic', 'glass', 'neon'];

/// 备用图标（Android/iOS 需要声明；默认除外）。
List<String> get alternateIcons =>
    allIcons.where((n) => n != defaultIcon).toList();

const Map<String, int> androidDensities = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

/// 备用 appiconset 的尺寸槽：与主 AppIcon 对齐（iPhone + iPad），并包含
/// iOS 26 图标堆栈所需的 1024×1024 营销图标。iOS 26 从 1024 生成
/// Liquid Glass 图标；备用集缺 1024 时 setAlternateIconName 可能报
/// OSStatus -54（真机切换失败）。
const List<({int px, String label, String idiom, String scale, String size})>
    _iosIconSlots = [
  (px: 40, label: '20@2x', idiom: 'iphone', scale: '2x', size: '20x20'),
  (px: 60, label: '20@3x', idiom: 'iphone', scale: '3x', size: '20x20'),
  (px: 29, label: '29@1x', idiom: 'iphone', scale: '1x', size: '29x29'),
  (px: 58, label: '29@2x', idiom: 'iphone', scale: '2x', size: '29x29'),
  (px: 87, label: '29@3x', idiom: 'iphone', scale: '3x', size: '29x29'),
  (px: 40, label: '40@1x', idiom: 'iphone', scale: '1x', size: '40x40'),
  (px: 80, label: '40@2x', idiom: 'iphone', scale: '2x', size: '40x40'),
  (px: 120, label: '40@3x', idiom: 'iphone', scale: '3x', size: '40x40'),
  (px: 57, label: '57@1x', idiom: 'iphone', scale: '1x', size: '57x57'),
  (px: 114, label: '57@2x', idiom: 'iphone', scale: '2x', size: '57x57'),
  (px: 120, label: '60@2x', idiom: 'iphone', scale: '2x', size: '60x60'),
  (px: 180, label: '60@3x', idiom: 'iphone', scale: '3x', size: '60x60'),
  (px: 72, label: '72@1x', idiom: 'ipad', scale: '1x', size: '72x72'),
  (px: 144, label: '72@2x', idiom: 'ipad', scale: '2x', size: '72x72'),
  (px: 76, label: '76@1x', idiom: 'ipad', scale: '1x', size: '76x76'),
  (px: 152, label: '76@2x', idiom: 'ipad', scale: '2x', size: '76x76'),
  (px: 167, label: '83.5@2x', idiom: 'ipad', scale: '2x', size: '83.5x83.5'),
  (px: 1024, label: '1024', idiom: 'ios-marketing', scale: '1x', size: '1024x1024'),
];

/// 无 alpha 的 RGB PNG（iOS appiconset 要求不透明、且不得含 alpha 通道）。
List<int> _encodeRgb(img.Image src) {
  final rgb = img.Image(width: src.width, height: src.height, numChannels: 3);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      rgb.setPixelRgb(x, y, p.r, p.g, p.b);
    }
  }
  return img.encodePng(rgb);
}

img.Image _resize(img.Image src, int size) => img.copyResize(src,
    width: size, height: size, interpolation: img.Interpolation.cubic);

void _write(String path, List<int> bytes) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(bytes);
}

void main() {
  final sources = <String, img.Image>{};
  for (final name in allIcons) {
    final f = File('assets/icon/$name.png');
    if (!f.existsSync()) {
      stderr.writeln('缺少源图: ${f.path}');
      exit(1);
    }
    sources[name] = img.decodePng(f.readAsBytesSync())!;
  }

  // Android 备用图标
  for (final name in alternateIcons) {
    final src = sources[name]!;
    androidDensities.forEach((density, size) {
      _write(
        'android/app/src/main/res/mipmap-$density/ic_launcher_$name.png',
        img.encodePng(_resize(src, size)),
      );
    });
  }

  // iOS 备用图标：Asset Catalog appiconset（iPhone + iPad + 1024 营销），无 alpha
  for (final name in alternateIcons) {
    final src = sources[name]!;
    final dir = 'ios/Runner/Assets.xcassets/$name.appiconset';
    Directory(dir).createSync(recursive: true);
    // 清掉旧生成文件，避免尺寸集调整后残留
    for (final f in Directory(dir).listSync()) {
      if (f is File && f.path.endsWith('.png')) f.deleteSync();
    }
    final images = <Map<String, String>>[];
    for (final slot in _iosIconSlots) {
      final file = '$name-${slot.label}.png';
      _write('$dir/$file', _encodeRgb(_resize(src, slot.px)));
      images.add({
        'filename': file,
        'idiom': slot.idiom,
        'scale': slot.scale,
        'size': slot.size,
      });
    }
    _write(
      '$dir/Contents.json',
      utf8.encode(JsonEncoder.withIndent('  ').convert({
        'images': images,
        'info': {'version': 1, 'author': 'xcode'},
      })),
    );
  }

  // 设置页预览（含默认）
  for (final name in allIcons) {
    _write(
        'assets/icons/$name.png', img.encodePng(_resize(sources[name]!, 256)));
  }

  stdout.writeln('已生成：Android 备用图标 ${alternateIcons.length} 套、'
      'iOS 备用 appiconset ${alternateIcons.length} 套（含 iPad + 1024）、'
      '预览 ${allIcons.length} 张。默认图标=$defaultIcon');
}
