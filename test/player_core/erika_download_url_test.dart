import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 609：erika 预编译包下载地址（上游仓库改名 Erika → liberika）。
void main() {
  final windowsCmake = File(
    'third_party/erika_flutter/windows/build_erika_runtime.cmake',
  ).readAsStringSync();
  final ohosCmake = File(
    'third_party/erika_flutter/ohos/src/main/cpp/CMakeLists.txt',
  ).readAsStringSync();
  final androidGradle = File(
    'third_party/erika_flutter/android/erika-native.gradle',
  ).readAsStringSync();

  group('① 三处下载地址都指向 liberika', () {
    test('Windows CMake', () {
      expect(
        windowsCmake,
        contains('https://github.com/AimesSoft/liberika/releases/download/'),
      );
      expect(
        windowsCmake,
        isNot(contains('https://github.com/AimesSoft/Erika/releases/download/')),
      );
    });

    test('OHOS CMake', () {
      expect(
        ohosCmake,
        contains('https://github.com/AimesSoft/liberika/releases/download/'),
      );
      expect(
        ohosCmake,
        isNot(contains('https://github.com/AimesSoft/Erika/releases/download/')),
      );
    });

    test('Android gradle', () {
      expect(
        androidGradle,
        contains('https://github.com/AimesSoft/liberika/releases/download/'),
      );
      expect(
        androidGradle,
        isNot(contains('https://github.com/AimesSoft/Erika/releases/download/')),
      );
    });
  });

  group('② 全仓库不再有旧下载地址（防同步上游时回退）', () {
    test('构建脚本里不得出现 AimesSoft/Erika/releases/download', () {
      final hits = <String>[];
      for (final dir in const ['third_party', 'plugins', 'android', 'ohos']) {
        final d = Directory(dir);
        if (!d.existsSync()) continue;
        for (final f in d.listSync(recursive: true)) {
          if (f is! File) continue;
          final name = f.path;
          if (!(name.endsWith('.cmake') ||
              name.endsWith('.gradle') ||
              name.endsWith('.txt') ||
              name.endsWith('.yml') ||
              name.endsWith('.yaml'))) {
            continue;
          }
          try {
            final content = f.readAsStringSync();
            if (content.contains('AimesSoft/Erika/releases/download')) {
              hits.add(name);
            }
          } catch (_) {
            // 二进制/不可读文件跳过。
          }
        }
      }
      expect(hits, isEmpty, reason: '旧地址会 404：$hits');
    });
  });

  group('③ 注释记录改名原因（防误回退）', () {
    test('Windows CMake 有改名说明', () {
      expect(windowsCmake, contains('AimesSoft/Erika 已改名为 AimesSoft/liberika'));
    });

    test('OHOS CMake 有改名说明', () {
      expect(ohosCmake, contains('AimesSoft/Erika 已改名为 AimesSoft/liberika'));
    });

    test('Android gradle 有改名说明', () {
      expect(androidGradle, contains('AimesSoft/Erika 已改名为'));
    });
  });

  group('④ SHA 校验值保持不变（包内容未变，只换域名）', () {
    test('native_artifacts.properties 仍声明 windows/ohos SHA', () {
      final props = File(
        'third_party/erika_flutter/native_artifacts.properties',
      ).readAsStringSync();
      expect(
        props,
        contains(
          'ERIKA_WINDOWS_X64_SHA256=c563424ebc6f9c6bce1f71e7afea0e48fd6f8dff052ac5893fb42c5ee2764063',
        ),
      );
      expect(
        props,
        contains(
          'ERIKA_OPENHARMONY_ARM64_SHA256=4f66f5f359458ef692c8f01aeffcbdb922b2f0fa78f3da83002fe5ff72752c81',
        ),
      );
    });
  });
}
