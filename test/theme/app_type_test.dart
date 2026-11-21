import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/theme/app_type.dart';

void main() {
  group('AppType 字号档（698 N10-B）', () {
    test('六档 + 微档 + 正文行距 1.5', () {
      expect(AppType.micro, 10);
      expect(AppType.caption, 11);
      expect(AppType.small, 12);
      expect(AppType.body, 13);
      expect(AppType.emphasis, 15);
      expect(AppType.title, 18);
      expect(AppType.display, 24);
      expect(AppType.bodyLineHeight, 1.5, reason: '简介/描述行距统一 1.5');
    });

    test('碎值清零守卫（698 N10-B）：lib/ 无小数字号', () {
      // 小数字号让 Flutter 与 QML/ArkTS 原生面板字号无法对齐（QML
      // font.pixelSize 只收整数）——碎值一律取整进档。
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final matches =
            RegExp(r'fontSize:\s*\d+\.\d+').allMatches(f.readAsStringSync());
        for (final m in matches) {
          offenders.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(offenders, isEmpty,
          reason: '发现小数字号（应取整进 AppType 档）：$offenders');
    });
  });

  group('MiSans 字体声明（698 N10-A）', () {
    // pubspec 正则解析（不引 yaml 传递依赖）。
    final pubspecText = File('pubspec.yaml').readAsStringSync();

    test('pubspec 声明 MiSans 四字重（400/500/600/700）', () {
      expect(pubspecText, contains('family: MiSans'));
      final weights = RegExp(
        r'MiSans-\w+\.ttf\s*\n\s*weight:\s*(\d+)',
      ).allMatches(pubspecText).map((m) => m.group(1)).toList();
      // 第一档（Regular）无显式 weight = 400。
      expect(weights, ['500', '600', '700']);
      expect(
        RegExp(r'MiSans-Regular\.ttf').hasMatch(pubspecText),
        isTrue,
        reason: 'Regular 档（400）缺省 weight 声明',
      );
    });

    test('字体子集文件在仓且每档 ≤ 3MB（子集化生效）', () {
      final assets = RegExp(r'asset: (third_party/misans/fonts/[\w.-]+)')
          .allMatches(pubspecText)
          .map((m) => m.group(1)!)
          .toList();
      expect(assets, hasLength(4), reason: '四字重四个子集文件');
      for (final path in assets) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path 缺失');
        expect(file.lengthSync(), lessThanOrEqualTo(3 * 1024 * 1024),
            reason: '$path 超 3MB（子集化回退？）');
      }
    });

    test('许可署名在仓（公开库合规：third_party/misans/）', () {
      expect(File('third_party/misans/NOTICE.md').existsSync(), isTrue);
      expect(File('third_party/misans/LICENSE').existsSync(), isTrue);
    });
  });
}
