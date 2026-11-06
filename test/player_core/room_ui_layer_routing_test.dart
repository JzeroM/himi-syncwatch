import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 613：房间 UI 渲染层跟随播放器内核（不等 prepare 有媒体才决定）。
void main() {
  final adapter = File('lib/services/player/mpv_player_adapter.dart')
      .readAsStringSync();
  final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
  final gating = File('lib/services/player/native/native_player_gating.dart')
      .readAsStringSync();

  group('① prefersNativeRoomUi 是纯计算（不建会话）', () {
    test('getter 存在且只读设置', () {
      expect(adapter, contains('bool get prefersNativeRoomUi {'));
      final idx = adapter.indexOf('bool get prefersNativeRoomUi {');
      final body = adapter.substring(idx, idx + 800);
      expect(body, contains('_resolveMpvVideoOutput()'));
      expect(body, contains('NativePlayerGating.shouldUseCurrent'));
      // 不得创建会话。
      expect(body, isNot(contains('MpvSessionPlatform.create')));
      expect(body, isNot(contains('await ')));
    });

    test('注释记录「原生 UI 只在 prepare 里打开」根因', () {
      expect(adapter, contains('原生 UI 只在'));
      expect(adapter, contains('`prepare()` 里打开'));
    });

    test('门控语义仍是 engine=mpv + surface + 平台支持', () {
      expect(gating, contains("engine == 'mpv'"));
      expect(gating, contains("actualVideoOutput == 'surface'"));
      expect(gating, contains("supportedPlatforms = <String>{'android', 'ohos'}"));
    });
  });

  group('② _openNativeUiIfNeeded 允许在 prepare 前打开', () {
    test('614：补算只在鸿蒙生效、且不写回 _nativeUiEnabled', () {
      final idx = adapter.indexOf('Future<void> _openNativeUiIfNeeded({');
      expect(idx, greaterThan(0));
      final body = adapter.substring(idx, idx + 900);
      // 614 起安卓回退：补算有 isOhos 守卫。
      expect(body, contains('if (!MpvSessionPlatform.isOhos) return;'));
      // 不写回字段（避免跨会话残留）。
      expect(body, isNot(contains('_nativeUiEnabled = prefersNativeRoomUi;')));
      // 守卫不再要求 _nativeUiEnabled 预先为 true。
      expect(body, isNot(contains('if (!_nativeUiEnabled || _disposed')));
    });
  });

  group('③ _roomUiShouldBeNative 用于 _buildVideoArea', () {
    test('getter 存在', () {
      expect(screen, contains('bool get _roomUiShouldBeNative {'));
    });

    test('房间模式用新判定、非房间模式仍用 nativeUiActive', () {
      final idx = screen.indexOf('final nativeShortCircuit');
      expect(idx, greaterThan(0));
      final body = screen.substring(idx, idx + 300);
      expect(body, contains('widget.roomCode != null'));
      expect(body, contains('_roomUiShouldBeNative'));
      expect(body, contains('_nativeUiActive'));
    });

    test('注释记录「_roomData 在 async 里才赋值」根因', () {
      expect(screen, contains('`_setupRoomSync()` 里才满足'));
    });
  });

  group('④ initState 按判定打开原生窗口 + _roomData 同步解码', () {
    test('_roomData 在 initState 同步赋值（不是 ??= 等 async）', () {
      final idx = screen.indexOf('_roomData = RoomCode.decode(widget.roomCode!);');
      expect(idx, greaterThan(0));
      // 必须是 `=` 而非 `??=`（??= 在 _setupRoomSync 里是兜底）。
      final initIdx = screen.indexOf('void initState()');
      expect(idx, greaterThan(initIdx));
      final body = screen.substring(idx - 200, idx + 100);
      expect(body, contains('纯同步解码'));
    });

    test('initState 里房间模式按判定调 reopenNativeUi', () {
      final idx = screen.indexOf('_roomData = RoomCode.decode(widget.roomCode!);');
      final body = screen.substring(idx, idx + 800);
      expect(body, contains('prefersNativeRoomUi'));
      expect(body, contains('reopenNativeUi()'));
    });
  });

  group('⑤ 切换内核时重新判定房间 UI 层', () {
    test('_switchPlayerKernel 的 finally 里重新判定', () {
      final idx = screen.indexOf('Future<void> _switchPlayerKernel(');
      expect(idx, greaterThan(0));
      final end = screen.indexOf('/// 选集按钮（底栏音轨右侧', idx);
      final body = screen.substring(idx, end);
      expect(body, contains('prefersNativeRoomUi'));
      expect(body, contains('reopenNativeUi()'));
      expect(body, contains('closeNativeUi()'));
    });

    test('注释记录「切内核后不重新判定」的旧问题', () {
      expect(screen, contains('切到 MDK 后仍是原生房'));
    });
  });
}
