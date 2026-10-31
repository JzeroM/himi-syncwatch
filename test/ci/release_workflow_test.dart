import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CI 发布工作流防回归：`build-android` 的磁盘与 runner 约束。
///
/// 背景（v1.5.5-debug27，run 41167128508）：`build-android` 在
/// `flutter build apk --release --split-per-abi` 中途把 runner 磁盘写满，
/// 抛 `System.IO.IOException: No space left on device`。更糟的是连 job 日志
/// blob 都没写成功（logs 端点返回 `BlobNotFound`），线上只能看到
/// `Gradle task assembleRelease failed`，排查成本极高。
///
/// 同仓库 `android-hdr-ci.yml` / `mpv-kernels.yml` 一直有清理步骤所以从没炸过，
/// 唯独 release.yml 的 build-android 漏了。本测试锁住三件事：
///   1. 清理步骤存在且覆盖主要预装 SDK；
///   2. 绝不误删 `/usr/local/lib/android`（本 job 的 Android SDK 依赖，
///      从 mpv-kernels.yml 复制清理清单时最容易带进来的致命错误）；
///   3. 构建步骤打印磁盘余量，且 runner 固定版本（ubuntu-latest 自
///      2026-10-19 起迁移 Ubuntu 26，镜像体积会漂）。
void main() {
  final workflow = File('.github/workflows/release.yml').readAsStringSync();

  /// 截取某个 job 的配置段：从 `  <name>:` 到下一个同级 job 键为止。
  String jobSection(String name) {
    final start = workflow.indexOf('\n  $name:\n');
    expect(start, greaterThan(-1), reason: 'release.yml 缺少 job: $name');
    final rest = workflow.substring(start + 1);
    final next = RegExp(r'\n  [a-zA-Z][a-zA-Z0-9_-]*:\n').firstMatch(rest.substring(name.length + 3));
    final end = next == null ? rest.length : name.length + 3 + next.start;
    return rest.substring(0, end);
  }

  group('build-android 磁盘约束', () {
    late String android;

    setUpAll(() => android = jobSection('build-android'));

    test('存在释放磁盘空间步骤', () {
      expect(
        android,
        contains('name: 释放磁盘空间'),
        reason: '缺清理步骤会导致 runner 盘满，且失败时日志 blob 丢失',
      );
    });

    test('清理清单覆盖主要预装 SDK', () {
      for (final dir in <String>[
        '/usr/share/dotnet',
        '/opt/ghc',
        '/opt/hostedtoolcache/CodeQL',
        '/usr/share/swift',
        '/usr/share/miniconda',
      ]) {
        expect(android, contains(dir), reason: '清理清单缺少 $dir');
      }
    });

    test('绝不删除 /usr/local/lib/android（本 job 依赖的 Android SDK）', () {
      expect(
        android,
        isNot(contains('rm -rf /usr/local/lib/android')),
        reason: '删掉预装 Android SDK 会让 flutter build apk 直接失败',
      );
    });

    test('清理 Android SDK 内无用组件但保留 platforms/ndk', () {
      expect(android, contains(r'$ANDROID_HOME/system-images'));
      expect(android, contains(r'$ANDROID_HOME/emulator'));
      expect(
        android,
        isNot(contains(r'$ANDROID_HOME/platforms')),
        reason: 'platforms/build-tools 是构建必需，不能删',
      );
      expect(
        android,
        isNot(contains(r'$ANDROID_HOME/ndk')),
        reason: 'NDK 是原生插件（fvp/media_kit）构建必需，不能删',
      );
    });

    test('构建步骤打印磁盘余量', () {
      expect(
        android,
        contains('df -h /'),
        reason: '盘满时 runner 写不出日志，构建前必须自证余量',
      );
    });

    test('可用空间不足时 fail fast 并给出明确原因', () {
      expect(
        android,
        contains('::error::清理后可用空间仅'),
        reason: '盘满会吞掉日志，必须提前失败并写明原因',
      );
    });

    test('runner 固定 ubuntu-24.04 而非 ubuntu-latest', () {
      final runsOn = RegExp(r'runs-on:\s*(\S+)').firstMatch(android);
      expect(runsOn, isNotNull, reason: 'build-android 缺少 runs-on');
      expect(
        runsOn!.group(1),
        'ubuntu-24.04',
        reason: 'ubuntu-latest 自 2026-10-19 起迁移 Ubuntu 26，镜像体积会漂',
      );
    });
  });

  test('其他构建 job 未被误改（仍各自保留清理步骤）', () {
    for (final f in <String>[
      '.github/workflows/android-hdr-ci.yml',
      '.github/workflows/mpv-kernels.yml',
    ]) {
      expect(
        File(f).readAsStringSync(),
        contains('Free disk space'),
        reason: '$f 的清理步骤是既有防线，不能删',
      );
    }
  });
}
