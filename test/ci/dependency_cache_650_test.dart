import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 650：CI 外部依赖缓存 + 验证型 CI 改为手动触发。
///
/// 【背景】v1.5.69 / v1.5.70 的 CI 反复失败，但**代码本身没问题**
/// （同一 run 里 Android 构建成功）：
/// - Windows：fvp 的 `mdk-sdk-windows-x64.7z` 下载 3 次均失败
/// - iOS：`mdk-sdk-apple.zip` 下载 `badResponseStatusCode(504)`
/// - Android：`erika-flutter-android-x86_64.zip` 下载失败
/// 均为 GitHub Releases 侧故障。
///
/// 治本：用 `actions/cache` 缓存这些固定版本的依赖，命中后跳过下载。
///
/// 另一个问题：一个 commit 会触发 3 个 workflow（release + windows-mpv-ci
/// + android-hdr-ci），构建内容高度重叠 → 两个验证型 CI 改为仅手动。
void main() {
  String read(String p) => File(p).readAsStringSync();

  const releaseYml = '.github/workflows/release.yml';
  const androidCi = '.github/workflows/android-hdr-ci.yml';
  const windowsCi = '.github/workflows/windows-mpv-ci.yml';

  group('① 三平台依赖缓存（治本）', () {
    late String yml;

    setUp(() => yml = read(releaseYml));

    test('Windows 缓存 fvp 的 MDK SDK', () {
      final start = yml.indexOf('build-windows:');
      expect(start, greaterThan(-1));
      final body = yml.substring(start);
      expect(body, contains('actions/cache@v4'));
      expect(
        body,
        contains('third_party/fvp/mdk-sdk-windows-x64.7z'),
        reason: 'fvp deps.cmake 把包下载到插件目录（MDK_SDK_SAVE）',
      );
      // key 用 SHA256 版本标识 → 换 SDK 版本时自动失效。
      expect(body, contains('FVP_DEPS_SHA256'));
    });

    test('iOS 缓存 Swift Package Manager 依赖', () {
      final start = yml.indexOf('build-ios:');
      expect(start, greaterThan(-1));
      final body = yml.substring(start, start + 4000);
      expect(body, contains('actions/cache@v4'));
      expect(body, contains('org.swift.swiftpm'));
      expect(body, contains('SourcePackages'));
    });

    test('Android 缓存 Erika 预编译包 + MDK SDK', () {
      final start = yml.indexOf('build-android:');
      expect(start, greaterThan(-1));
      final body = yml.substring(start, start + 9000);
      expect(body, contains('actions/cache@v4'));
      expect(body, contains('.gradle/caches/erika'));
      expect(body, contains('third_party/fvp/mdk-sdk-android.7z'));
    });

    test('缓存步骤在构建步骤之前', () {
      // Windows：缓存必须在 `flutter build windows` 之前。
      final winStart = yml.indexOf('build-windows:');
      final winBody = yml.substring(winStart);
      final cacheIdx = winBody.indexOf('Cache MDK SDK');
      final buildIdx = winBody.indexOf('flutter build windows --release');
      expect(cacheIdx, greaterThan(-1));
      expect(buildIdx, greaterThan(cacheIdx), reason: '缓存要在构建前恢复');

      // Android：缓存必须在 `flutter build apk` 之前。
      final andStart = yml.indexOf('build-android:');
      final andBody = yml.substring(andStart, andStart + 9000);
      final andCache = andBody.indexOf('Cache Erika + MDK SDK');
      final andBuild = andBody.indexOf('flutter build apk --release');
      expect(andCache, greaterThan(-1));
      expect(andBuild, greaterThan(andCache));
    });
  });

  group('② 验证型 CI 改为仅手动触发', () {
    test('android-hdr-ci 只保留 workflow_dispatch', () {
      final src = read(androidCi);
      final onStart = src.indexOf('on:');
      expect(onStart, greaterThan(-1));
      final onBlock = src.substring(onStart, onStart + 1200);
      expect(onBlock, contains('workflow_dispatch'));
      expect(
        onBlock,
        isNot(contains('push:')),
        reason: '推 commit 不应再触发（与 release.yml 重叠）',
      );
    });

    test('windows-mpv-ci 只保留 workflow_dispatch', () {
      final src = read(windowsCi);
      final onStart = src.indexOf('on:');
      expect(onStart, greaterThan(-1));
      final onBlock = src.substring(onStart, onStart + 1400);
      expect(onBlock, contains('workflow_dispatch'));
      expect(
        onBlock,
        isNot(contains('push:')),
        reason: '推 commit 不应再触发（与 release.yml 重叠）',
      );
    });

    test('release.yml 仍由 tag 触发（发布入口不变）', () {
      final src = read(releaseYml);
      final onStart = src.indexOf('on:');
      final onBlock = src.substring(onStart, onStart + 300);
      expect(onBlock, contains('tags:'));
      expect(onBlock, contains("'v*'"));
    });
  });

  group('③ release.yml 不依赖被改的两个验证 CI', () {
    test('kernels job 只查 mpv-kernels.yml', () {
      final src = read(releaseYml);
      final start = src.indexOf('kernels:');
      expect(start, greaterThan(-1));
      final body = src.substring(start, start + 2000);
      expect(body, contains('mpv-kernels.yml'));
      expect(body, isNot(contains('android-hdr-ci')));
      expect(body, isNot(contains('windows-mpv-ci')));
    });
  });
}
