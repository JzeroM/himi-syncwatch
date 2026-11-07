import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 635：重进房 / 房主重开房后加入 → 资源列表为空、约 20 秒后被踢。
///
/// **634 的判断不完整**：`_listening` 复位只是必要条件，真正根因在 ArkTS 侧。
///
/// 完整根因链：
/// 1. `RtmManager.release()` 末尾 `this.sink = null` 清空了事件出口。
/// 2. `initialize()` 开头若已有实例会先调 `release()` 重建 client，
///    重建后 **没有任何地方恢复 sink**。
/// 3. `emit()` 里 `if (this.sink !== null)` 恒为假 → **所有事件被丢弃**。
///
/// 为什么 `onListen` 没能救回来：
/// 若 `RtmService` provider 未销毁（第二次进房复用同一实例），
/// EventChannel 订阅从未断开，`onListen` 不会再次触发 → sink 永远为 null。
///
/// 真机表现完全吻合：
/// - 在线人数正常（`whoNow` 直调 MethodChannel，不经 sink）
/// - 播报正常（本地 `_addBroadcastMessage`，不经 sink）
/// - **资源列表为空**（roomInfo 走 emit → sink 为 null → 丢弃）
/// - **约 20 秒后被踢**（收不到 roomInfo → `_roomInfoTimeout` → 误判解散）
///
/// Windows 不受影响：`RtmClient::Release()` 只清 client 指针，不动
/// `event_sink_`；后者仅在 Dart 侧 `onCancel` 时重置。
void main() {
  final manager = File(
    'plugins/himi_ohos_rtm/ohos/src/main/ets/RtmManager.ets',
  ).readAsStringSync();
  final plugin = File(
    'plugins/himi_ohos_rtm/ohos/src/main/ets/HimiOhosRtmPlugin.ets',
  ).readAsStringSync();
  final windowsNative = File(
    'plugins/himi_windows_rtm/windows/rtm_client.cpp',
  ).readAsStringSync();

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

  group('① ArkTS RtmManager.release 不再清空 sink', () {
    test('release 内无 this.sink = null', () {
      final body = stripComments(bodyOf(manager, 'release(): void {'));
      expect(
        body,
        isNot(contains('this.sink = null')),
        reason: 'sink 是事件出口，与 client 实例生命周期无关；'
            '清空后重建 client 时无人恢复 → emit 全部丢弃',
      );
    });

    test('release 仍释放 instanceId', () {
      final body = bodyOf(manager, 'release(): void {');
      expect(body, contains('releaseRtmClient(this.instanceId)'));
      expect(body, contains('this.instanceId = -1'));
    });

    test('emit 仍检查 sink 非空（防御性）', () {
      final body = stripComments(bodyOf(manager, 'private emit('));
      expect(body, contains('this.sink !== null'));
    });
  });

  group('② Plugin 提供 _attachSink 并双点调用', () {
    test('新增 _attachSink 方法', () {
      expect(plugin, contains('private _attachSink(): void {'));
      final body = bodyOf(plugin, 'private _attachSink(): void {');
      expect(body, contains('this.manager.setEventSink'));
    });

    test('onListen 调用 _attachSink', () {
      final body = stripComments(bodyOf(plugin, 'onListen: (args: Object, sink: EventSink): void => {'));
      expect(body, contains('this._attachSink()'));
    });

    test('initialize 分支调用 _attachSink（兜底重建 client 后恢复出口）', () {
      final idx = plugin.indexOf("case 'initialize':");
      expect(idx, greaterThan(0));
      final end = plugin.indexOf("case 'login':", idx);
      final body = stripComments(plugin.substring(idx, end));
      expect(
        body,
        contains('this._attachSink()'),
        reason: 'initialize 内部会先 release() 重建 client，必须重挂出口',
      );
    });

    test('onCancel 只清 eventSink，不主动清 manager.sink', () {
      final body = stripComments(bodyOf(plugin, 'onCancel: (args: Object): void => {'));
      expect(body, contains('this.eventSink = null'));
      expect(
        body,
        isNot(contains('setEventSink(null)')),
        reason: 'Dart 侧重订阅时 onListen 会立刻重挂，避免中间窗口丢事件',
      );
    });

    test('onDetachedFromEngine 才真正清空出口', () {
      final body = stripComments(bodyOf(plugin, 'onDetachedFromEngine('));
      expect(body, contains('this.manager.setEventSink(null)'));
      expect(body, contains('this.eventSink = null'));
    });
  });

  group('③ Windows 不受影响（对照验证）', () {
    test('RtmClient::Release 不清 event_sink_', () {
      final body = stripComments(bodyOf(windowsNative, 'void RtmClient::Release() {'));
      expect(
        body,
        isNot(contains('event_sink_')),
        reason: 'Windows 的 event_sink_ 由 StreamHandler 管理，Release 不应触碰',
      );
      // 注意：不能对 C++ 源码用 stripComments（`->` 会被误当注释起点）。
      expect(body, contains('release()'));
    });
  });

  group('④ 回归锁：sink 生命周期只由 Plugin 管理', () {
    test('RtmManager 中 sink 的写入点仅 setEventSink', () {
      // release 不再写 sink；initialize 也不应写。
      final initBody = stripComments(bodyOf(manager, 'initialize(appId: string, userId: string): void {'));
      expect(initBody, isNot(contains('this.sink =')));
      final releaseBody = stripComments(bodyOf(manager, 'release(): void {'));
      expect(releaseBody, isNot(contains('this.sink =')));
    });
  });
}
