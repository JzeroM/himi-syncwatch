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

/// appiconset 的 Contents.json 模板（%s 为图标名）。尺寸与旧散装文件一致。
const String _appIconSetContents = '''{
  "images" : [
    {
      "size" : "60x60",
      "idiom" : "iphone",
      "filename" : "%s@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "60x60",
      "idiom" : "iphone",
      "filename" : "%s@3x.png",
      "scale" : "3x"
    },
    {
      "size" : "76x76",
      "idiom" : "ipad",
      "filename" : "%s-76.png",
      "scale" : "1x"
    },
    {
      "size" : "76x76",
      "idiom" : "ipad",
      "filename" : "%s-76@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "83.5x83.5",
      "idiom" : "ipad",
      "filename" : "%s-83.5@2x.png",
      "scale" : "2x"
    }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
''';

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

  // iOS 备用图标：Asset Catalog appiconset（iPhone + iPad），无 alpha
  for (final name in alternateIcons) {
    final src = sources[name]!;
    final dir = 'ios/Runner/Assets.xcassets/$name.appiconset';
    _write('$dir/$name@2x.png', _encodeRgb(_resize(src, 120)));
    _write('$dir/$name@3x.png', _encodeRgb(_resize(src, 180)));
    _write('$dir/$name-76.png', _encodeRgb(_resize(src, 76)));
    _write('$dir/$name-76@2x.png', _encodeRgb(_resize(src, 152)));
    _write('$dir/$name-83.5@2x.png', _encodeRgb(_resize(src, 167)));
    _write(
        '$dir/Contents.json', utf8.encode(_appIconSetContents.replaceAll('%s', name)));
  }

  // 设置页预览（含默认）
  for (final name in allIcons) {
    _write(
        'assets/icons/$name.png', img.encodePng(_resize(sources[name]!, 256)));
  }

  stdout.writeln('已生成：Android 备用图标 ${alternateIcons.length} 套、'
      'iOS 备用 appiconset ${alternateIcons.length} 套（含 iPad）、'
      '预览 ${allIcons.length} 张。默认图标=$defaultIcon');
}
