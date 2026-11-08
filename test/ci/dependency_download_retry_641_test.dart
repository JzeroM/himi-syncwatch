import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 641：CI 外部依赖下载加重试。
///
/// 起因：`v1.5.60` CI 的 Windows / iOS 双双失败，均与代码无关——
/// - Windows：`fvp/cmake/deps.cmake:79` `Failed to download
///   "HTTP response code said error"`（GitHub Releases 瞬时故障）；
/// - iOS：`media_kit_libs_ios_video/ios/Makefile` 的 `curl` 失败 →
///   `Frameworks/` 为空 → Swift 报 `Cannot find 'mpv_error_string' in scope`。
///
/// 两处原本都是「一次失败即终止」，把偶发网络抖动放大成流水线失败。
void main() {
  group('641 CI 依赖下载重试', () {
    test('fvp deps.cmake 的下载函数有 3 次重试', () {
      final src = File('third_party/fvp/cmake/deps.cmake').readAsStringSync();
      final start = src.indexOf('function(_fvp_download_file');
      expect(start, greaterThan(-1));
      final end = src.indexOf('endfunction()', start);
      final body = src.substring(start, end);

      // 重试循环。
      expect(body, contains('foreach(ATTEMPT RANGE 1 3)'));
      // 成功即跳出。
      expect(body, contains('set(DOWNLOAD_OK TRUE)'));
      expect(body, contains('break()'));
      // 失败后清残片（否则 .part 会污染下次下载）。
      expect(body, contains(r'file(REMOVE "${PARTIAL_OUTPUT}")'));
      // 退避（CMake 3.17 无内置 sleep，用 -E sleep）。
      expect(body, contains('-E sleep'));
      // 超时保护：单次下载不得无限挂起。
      expect(body, contains('TIMEOUT 600'));
      // 最终失败才报错，且带尝试次数说明。
      expect(body, contains('after 3 attempts'));
    });

    test('fvp deps.cmake 只在 3 次都失败后才 FATAL_ERROR', () {
      final src = File('third_party/fvp/cmake/deps.cmake').readAsStringSync();
      final start = src.indexOf('function(_fvp_download_file');
      final end = src.indexOf('endfunction()', start);
      final body = src.substring(start, end);

      final fatalIdx = body.indexOf('message(FATAL_ERROR');
      final loopEnd = body.indexOf('endforeach()');
      expect(fatalIdx, greaterThan(loopEnd),
          reason: 'FATAL_ERROR 必须在重试循环之外');
    });

    test('iOS Makefile 的 curl 有重试与 --fail', () {
      final src = File(
        'third_party/nipaplay/media-kit-upstream/libs/ios/'
        'media_kit_libs_ios_video/ios/Makefile',
      ).readAsStringSync();

      expect(src, contains('--retry 5'));
      expect(src, contains('--retry-delay 5'));
      expect(src, contains('--retry-all-errors'));
      // --fail 很关键：否则 4xx/5xx 会被当成成功写进文件，
      // 真实原因被后面的 shasum / Swift 编译错误掩盖。
      expect(src, contains('--fail'));
    });

    test('iOS Makefile 仍校验 SHA-256（重试不得绕过完整性校验）', () {
      final src = File(
        'third_party/nipaplay/media-kit-upstream/libs/ios/'
        'media_kit_libs_ios_video/ios/Makefile',
      ).readAsStringSync();
      expect(src, contains('shasum -a 256 -c'));
      expect(src, contains('MPV_XCFRAMEWORKS_SHA256SUM'));
    });

    test('Windows 构建步骤保留 3 次整体重试（CI 侧）', () {
      final src = File('.github/workflows/release.yml').readAsStringSync();
      expect(src, contains('for (\$i = 1; \$i -le 3; \$i++)'));
    });
  });
}
