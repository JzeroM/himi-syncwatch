import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 638：三个真机问题的防回归。
///
/// 1. **观众退房后房主在线人数未减**（仅鸿蒙）——ArkTS 侧 `getOnlineUsers`
///    用 `totalOccupancy`（服务端累计占用数）优先，观众离开后不一定回落；
///    Windows/安卓用 `userStateList` 的实际长度，故只有鸿蒙有此问题。
/// 2. **鸿蒙观众在房主未起播时进房被判解散**——`_scheduleHostOfflineCheck`
///    单次 `whoNow < 2` 即判定离线，而房主未起播时 presence 尚未同步。
/// 3. **Windows 开播闪退**——CI 注入自建 `libmpv-2.dll`（mpvbuild 1f8d2e7
///    + ffmpeg n9.0.2）在 texture/surface 两条路径都访问违例
///    （0xc0000005，偏移 0x1856fc / 0x84e31）。改为 media_kit 官方 +
///    shinchiro 完整版。
void main() {
  final arktsManager = File(
    'plugins/himi_ohos_rtm/ohos/src/main/ets/RtmManager.ets',
  ).readAsStringSync();
  final screen =
      File('lib/screens/player/player_screen.dart').readAsStringSync();
  final releaseYml = File('.github/workflows/release.yml').readAsStringSync();

  String stripComments(String src) => src
      .split('\n')
      .map((line) {
        final i = line.indexOf('//');
        return i >= 0 ? line.substring(0, i) : line;
      })
      .join('\n');

  String bodyOf(String src, String signature) {
    final idx = src.indexOf(signature);
    expect(idx, greaterThan(0), reason: '未找到 $signature');
    var depth = 0;
    var started = false;
    for (var i = idx + signature.length - 1; i < src.length; i++) {
      final ch = src[i];
      if (ch == '{') {
        depth++;
        started = true;
      } else if (ch == '}') {
        depth--;
        if (started && depth == 0) return src.substring(idx, i + 1);
      }
    }
    fail('$signature 的大括号未配平');
  }

  group('① 鸿蒙在线人数改用列表长度（不再用 totalOccupancy）', () {
    test('getOnlineUsers 的 count 来自 ids.length', () {
      final body = bodyOf(arktsManager, 'async getOnlineUsers(');
      expect(
        stripComments(body),
        contains("out.set('count', ids.length)"),
        reason: 'totalOccupancy 是累计占用数，观众离开后不一定回落',
      );
    });

    test('不再读取 totalOccupancy', () {
      final body = stripComments(bodyOf(arktsManager, 'async getOnlineUsers('));
      expect(
        body,
        isNot(contains('totalOccupancy')),
        reason: '真机回归「观众退房，房主人数未减」的直接根因',
      );
    });

    test('userIds 仍按 userStateList 收集（未受影响）', () {
      final body = bodyOf(arktsManager, 'async getOnlineUsers(');
      expect(body, contains('userStateList'));
      expect(body, contains('ids.push(uid)'));
    });
  });

  group('② 房主离线判定：连续两轮才确认', () {
    test('_scheduleHostOfflineCheck 支持 isSecondRound', () {
      expect(
        screen,
        contains('void _scheduleHostOfflineCheck({bool isSecondRound = false})'),
      );
    });

    test('首轮 count<2 时再等一轮，不直接解散', () {
      final body =
          stripComments(bodyOf(screen, 'void _scheduleHostOfflineCheck({bool isSecondRound = false}) {'));
      final firstRoundIdx = body.indexOf('if (!isSecondRound)');
      final dialogIdx = body.indexOf('_showRoomDestroyedDialog()');
      expect(firstRoundIdx, greaterThan(0));
      expect(dialogIdx, greaterThan(firstRoundIdx),
          reason: '首轮必须先 return，不能落到解散');
      expect(body, contains('_scheduleHostOfflineCheck(isSecondRound: true)'));
    });

    test('count >= 2 仍视为抖动忽略', () {
      final body =
          stripComments(bodyOf(screen, 'void _scheduleHostOfflineCheck({bool isSecondRound = false}) {'));
      expect(body, contains('if (count >= 2)'));
      expect(body, contains('抖动'));
    });
  });

  group('③ Windows 改用官方 libmpv（不再注入自建版）', () {
    test('CI 不再设置 MEDIA_KIT_LIBMPV_DIR', () {
      expect(
        releaseYml,
        isNot(contains('MEDIA_KIT_LIBMPV_DIR')),
        reason: '自建 libmpv 在 texture/surface 两条路径都 0xc0000005',
      );
    });

    test('CI 不再下载 windows-libmpv artifact', () {
      expect(releaseYml, isNot(contains('name: windows-libmpv')));
    });

    test('build-windows 不再依赖 kernels', () {
      final idx = releaseYml.indexOf('build-windows:');
      expect(idx, greaterThan(0));
      final head = releaseYml.substring(idx, idx + 400);
      expect(head, contains('needs: [flutter-analyze]'));
      expect(
        head,
        isNot(contains('needs: [flutter-analyze, kernels]')),
        reason: 'Windows 已不消费内核产物',
      );
    });

    test('仍保留 shinchiro 完整版替换步骤', () {
      expect(releaseYml, contains('shinchiro'));
      expect(releaseYml, contains('libmpv-2.dll'));
    });
  });
}
