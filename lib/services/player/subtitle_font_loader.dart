import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 把打包字体复制到应用支持目录，供 MDK/libass 作为字幕回退字体。
/// 与 NipaPlay 的实现保持一致；失败时返回 null，由系统字体兜底。
Future<Map<String, String>?> ensureSubtitleFontFromAsset({
  required String assetPath,
  String fileName = 'subfont.ttf',
}) async {
  try {
    final supportDir = await getApplicationSupportDirectory();
    final fontsDir = Directory('${supportDir.path}/subtitle_fonts');
    if (!await fontsDir.exists()) {
      await fontsDir.create(recursive: true);
    }

    final fontFile = File('${fontsDir.path}/$fileName');
    final byteData = await rootBundle.load(assetPath);
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    if (!await fontFile.exists() || await fontFile.length() != bytes.length) {
      await fontFile.writeAsBytes(bytes, flush: true);
    }
    return {'filePath': fontFile.path, 'directory': fontsDir.path};
  } catch (e) {
    debugPrint('SubtitleFontLoader: 准备字幕字体失败: $e');
    return null;
  }
}
