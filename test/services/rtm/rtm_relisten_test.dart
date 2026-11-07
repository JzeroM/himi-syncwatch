import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 634：重进房 / 房主重开房后加入 → 消息流永久失效（EventChannel 不重订阅）。
///
/// 真机现象：第一次进房正常；重进房或房主重开房后再加入 →
/// **在线人数与播报都正常，但资源列表为空**，约 20 秒后弹「房间已解散」
/// 并退回首页。
///
/// 根因链：
/// 1. `_listening` 是插件里的**静态**标志。
/// 2. `RtmService.dispose()` → `backend.dispose()` → 插件 `release()`：
///    取消了 EventChannel 订阅，却**没有复位 `_listening`**。
/// 3. 第二次 `_ensureListening()` 看到 `_listening == true` → 直接 return
///    → EventChannel 永不重新订阅。
/// 4. 消息流 / presence 流永久失效：
///    - 资源列表（roomInfo 走消息流）→ 空
///    - 房主离线检测（presence 流）→ 失效
///    - 20 秒 roomInfo 超时 → 误判解散 → 退回首页
/// 5. 在线人数走 `whoNow` **直调 MethodChannel**、播报是**本地添加**，
///    都不经过 EventChannel，故二者仍然正常——这正是该 bug 的典型特征。
///
/// 影响范围：鸿蒙插件与 Windows 插件**同源缺陷**（都是静态 `_listening`）。
/// 安卓走官方 `agora_rtm`（每次新建 client，无静态监听标志），不受影响。
void main() {
  final ohos = File(
    'plugins/himi_ohos_rtm/lib/himi_ohos_rtm.dart',
  ).readAsStringSync();
  final windows = File(
    'plugins/himi_windows_rtm/lib/himi_windows_rtm.dart',
  ).readAsStringSync();
  final service = File('lib/services/rtm_service.dart').readAsStringSync();

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

  group('① 鸿蒙插件：release 必须复位静态监听状态', () {
    test('新增 _resetListening', () {
      expect(ohos, contains('static Future<void> _resetListening() async {'));
      final body = bodyOf(ohos, 'static Future<void> _resetListening() async {');
      expect(body, contains('_eventSubscription?.cancel()'));
      expect(body, contains('_eventSubscription = null'));
      expect(body, contains('_listening = false'));
    });

    test('release 调用 _resetListening', () {
      final body = bodyOf(ohos, 'static Future<void> release() async {');
      expect(
        body,
        contains('_resetListening()'),
        reason: '不复位则第二次进房 EventChannel 永不重订阅',
      );
    });

    test('debugReset 复用 _resetListening（避免两套逻辑漂移）', () {
      expect(ohos, contains('static Future<void> debugReset() => _resetListening();'));
    });
  });

  group('② Windows 插件：同源缺陷一并修复', () {
    test('新增 _resetListening', () {
      expect(windows,
          contains('static Future<void> _resetListening() async {'));
      final body =
          bodyOf(windows, 'static Future<void> _resetListening() async {');
      expect(body, contains('_eventSubscription?.cancel()'));
      expect(body, contains('_listening = false'));
    });

    test('release 调用 _resetListening', () {
      final body = bodyOf(windows, 'static Future<void> release() async {');
      expect(body, contains('_resetListening()'));
    });

    test('release 不再调用 _ensureListening（释放时建立订阅是错的）', () {
      final body = stripComments(
          bodyOf(windows, 'static Future<void> release() async {'));
      expect(
        body,
        isNot(contains('_ensureListening()')),
        reason: '释放时反而订阅，且会掩盖 _listening 未复位',
      );
    });
  });

  group('③ _ensureListening 增加订阅有效性自检', () {
    for (final (name, src) in [('鸿蒙', ohos), ('Windows', windows)]) {
      test('$name：标志为 true 但订阅已失效时能重新订阅', () {
        final body = stripComments(bodyOf(src, 'static void _ensureListening()'));
        expect(
          body,
          contains('_listening && _eventSubscription != null'),
          reason: '仅看标志位会陷入僵尸状态',
        );
      });
    }
  });

  group('④ RtmService.dispose 确保 backend 被释放', () {
    test('调用 _backend.dispose()', () {
      final body = bodyOf(service, 'void dispose()');
      expect(body, contains('_backend.dispose()'));
    });

    test('用 unawaited 显式表达不阻塞', () {
      final body = bodyOf(service, 'void dispose()');
      expect(body, contains('unawaited(_backend.dispose())'));
    });
  });

  group('⑤ 回归锁：两个插件都必须保留 _resetListening', () {
    for (final (name, src) in [('鸿蒙', ohos), ('Windows', windows)]) {
      test('$name：release 与 _ensureListening 双向配对', () {
        expect(src, contains('_resetListening'));
        final ensure = stripComments(bodyOf(src, 'static void _ensureListening()'));
        expect(ensure, contains('_eventSubscription != null'));
      });
    }
  });
}
