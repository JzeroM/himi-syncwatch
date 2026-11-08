import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 636：Erika 预编译产物下载地址必须指向 `AimesSoft/liberika`。
///
/// 背景：上游仓库 `AimesSoft/Erika` 已改名为 **`AimesSoft/liberika`**，
/// 旧地址全部返回 404（实际下载到 9 字节 "Not Found"，SHA-256 校验必然
/// 失败）。
///
/// 609 轮次修过 Android（`erika-native.gradle`）与 Windows
/// （`build_erika_runtime.cmake`），但**漏了 Apple 分支**
/// （`native/prepare_apple_prebuilt.sh`）→ iOS CI 连续失败：
///   Error (Xcode): failed to download Erika prebuilt v0.2.1
///
/// 本测试锁死**三处**下载地址，防止从上游同步时回退。
void main() {
  const appleScript =
      'third_party/erika_flutter/native/prepare_apple_prebuilt.sh';
  const androidGradle =
      'third_party/erika_flutter/android/erika-native.gradle';
  const windowsCMake =
      'third_party/erika_flutter/windows/build_erika_runtime.cmake';

  group('① 三个平台的下载地址都必须用 liberika', () {
    for (final (name, path) in [
      ('Apple（iOS/tvOS/macOS）', appleScript),
      ('Android', androidGradle),
      ('Windows', windowsCMake),
    ]) {
      test('$name：引用 AimesSoft/liberika', () {
        final src = File(path).readAsStringSync();
        expect(
          src,
          contains('AimesSoft/liberika'),
          reason: '上游已改名，旧地址 404',
        );
      });

      test('$name：不得残留 releases/download 的旧 Erika 地址', () {
        final src = File(path).readAsStringSync();
        expect(
          src,
          isNot(contains('AimesSoft/Erika/releases/download')),
          reason: '旧下载地址返回 404（"Not Found" 9 字节），SHA 校验必失败',
        );
      });
    }
  });

  group('② Apple 脚本的具体形态', () {
    test('URL 变量指向 liberika', () {
      final src = File(appleScript).readAsStringSync();
      final urlLine = src
          .split('\n')
          .firstWhere((l) => l.trimLeft().startsWith('URL='),
              orElse: () => '');
      expect(urlLine, isNotEmpty, reason: '未找到 URL= 赋值');
      expect(urlLine, contains('AimesSoft/liberika/releases/download'));
      expect(urlLine, contains(r'$PREBUILT_TAG'));
      expect(urlLine, contains(r'$ASSET'));
    });

    test('保留 SHA-256 校验（不得因改 URL 而跳过校验）', () {
      final src = File(appleScript).readAsStringSync();
      expect(src, contains('verify_sha256'));
      expect(src, contains('shasum -a 256'));
      expect(src, contains('checksum mismatch'));
    });

    test('根因注释留档（609 / liberika）', () {
      final src = File(appleScript).readAsStringSync();
      expect(src, contains('609'));
      expect(src, contains('liberika'));
    });
  });

  group('③ 版本清单未变（SHA 与 liberika v0.2.1 一致）', () {
    test('ERIKA_NATIVE_VERSION 仍为 0.2.1', () {
      final props = File(
        'third_party/erika_flutter/native_artifacts.properties',
      ).readAsStringSync();
      expect(props, contains('ERIKA_NATIVE_VERSION=0.2.1'));
    });

    test('五个 Apple 平台的 SHA256 均已声明', () {
      final props = File(
        'third_party/erika_flutter/native_artifacts.properties',
      ).readAsStringSync();
      for (final key in [
        'ERIKA_IOS_SHA256',
        'ERIKA_TVOS_SHA256',
        'ERIKA_MACOS_ARM64_SHA256',
        'ERIKA_MACOS_X64_SHA256',
        'ERIKA_MACOS_UNIVERSAL_SHA256',
      ]) {
        expect(props, contains('$key='), reason: '缺少 $key');
      }
    });
  });
}
