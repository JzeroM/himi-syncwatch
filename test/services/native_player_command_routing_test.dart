import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/native/native_player_command.dart';
import 'package:himi_syncwatch/services/player/native/native_player_controller.dart';

/// Phase 2 命令路由矩阵（docs/native_player_command_routing.md）。
///
/// 契约：`NativePlayerCommand.fromMap` 覆盖全部 30 类，经
/// `NativePlayerController.handleNativeCommand` 逐条到达执行器——任何一类
/// 解析失败（返回 null → 打「未知命令」）即视为路由断裂。
void main() {
  /// 全 30 类命令的原始 map（原生侧真实发出的 JSON 形态）。
  final allCommands = <String, Map<Object?, Object?>>{
    'togglePlay': const {'type': 'togglePlay'},
    'seekTo': const {'type': 'seekTo', 'positionMs': 1000},
    'seekRelative': const {'type': 'seekRelative', 'deltaMs': -5000},
    'setVolume': const {'type': 'setVolume', 'volume': 0.5},
    'setSpeed': const {'type': 'setSpeed', 'speed': 1.5},
    'selectAudio': const {'type': 'selectAudio', 'id': 2},
    'selectSubtitle': const {'type': 'selectSubtitle', 'id': 1},
    'addSubtitle': const {'type': 'addSubtitle', 'url': 'http://x.srt'},
    'setSubtitleStyle': const {
      'type': 'setSubtitleStyle',
      'style': {'fontSize': 20.0, 'opacity': 0.9}
    },
    'setSubtitleDelay': const {'type': 'setSubtitleDelay', 'delayMs': 200.0},
    'selectEpisode': const {'type': 'selectEpisode', 'index': 3},
    'selectVersion': const {'type': 'selectVersion', 'index': 1},
    'switchEngine': const {'type': 'switchEngine', 'engine': 'mpv'},
    'setDecodeMode': const {'type': 'setDecodeMode', 'mode': 'hw'},
    'adjustDisplay': const {'type': 'adjustDisplay', 'key': 'zoom', 'value': 1.2},
    'toggleDanmaku': const {'type': 'toggleDanmaku'},
    'updateDanmakuSettings': const {
      'type': 'updateDanmakuSettings',
      'values': {'fontSize': 16}
    },
    'toggleRoomSync': const {'type': 'toggleRoomSync'},
    'sendRoomChat': const {'type': 'sendRoomChat', 'text': 'hi'},
    'takeScreenshot': const {'type': 'takeScreenshot'},
    'toggleDebug': const {'type': 'toggleDebug'},
    'setSegmentMark': const {'type': 'setSegmentMark', 'kind': 'intro', 'positionMs': 500},
    'requestBack': const {'type': 'requestBack'},
    'requestExit': const {'type': 'requestExit'},
  };

  group('Phase 2 命令路由矩阵', () {
    test('全部 30 类命令都能解析为非 null（无一落入 unknown）', () {
      // fromMap 返回 null = 该类没接线，路由断裂。
      for (final entry in allCommands.entries) {
        final cmd = NativePlayerCommand.fromMap(entry.value);
        expect(cmd, isNotNull,
            reason: '命令 ${entry.key} 解析为 null——fromMap 缺该 case');
      }
    });

    test('每类命令经 controller 到达执行器（type 与预期一致）', () async {
      final received = <String>[];
      final controller = NativePlayerController(
        onCommand: (cmd) async {
          received.add(cmd.toMap()['type'] as String);
        },
      );
      for (final raw in allCommands.values) {
        await controller.handleNativeCommand(raw);
      }
      await controller.dispose();

      // 到达执行器的数量 = 输入数量（无一被 unknown 分支吞掉）。
      expect(received.length, allCommands.length,
          reason: '有命令未到达执行器：$received');
      // 每个输入 type 都在接收列表里。
      for (final key in allCommands.keys) {
        expect(received, contains(key), reason: '命令 $key 未到达执行器');
      }
    });

    test('未知 type 被忽略、不抛出（前向兼容：老原生壳新命令）', () async {
      var called = 0;
      final controller = NativePlayerController(
        onCommand: (_) async => called++,
      );
      await controller.handleNativeCommand(const {'type': 'futureCommand'});
      expect(called, 0);
      await controller.dispose();
    });

    test('B 组 9 类（选集/版本/音轨/字幕/倍速/弹幕/样式/延迟）解析类型正确', () {
      // 这些是 Phase 2 第一批接线的，断言解析到具体子类。
      expect(NativePlayerCommand.fromMap(const {'type': 'selectEpisode', 'index': 0}),
          isA<SelectEpisode>());
      expect(NativePlayerCommand.fromMap(const {'type': 'selectVersion', 'index': 0}),
          isA<SelectVersion>());
      expect(NativePlayerCommand.fromMap(const {'type': 'selectAudio', 'id': 1}),
          isA<SelectAudio>());
      expect(NativePlayerCommand.fromMap(const {'type': 'selectSubtitle', 'id': 1}),
          isA<SelectSubtitle>());
      expect(NativePlayerCommand.fromMap(const {'type': 'addSubtitle', 'url': 'u'}),
          isA<AddSubtitle>());
      expect(NativePlayerCommand.fromMap(const {'type': 'setSpeed', 'speed': 2.0}),
          isA<SetSpeed>());
      expect(NativePlayerCommand.fromMap(const {'type': 'toggleDanmaku'}),
          isA<ToggleDanmaku>());
      expect(NativePlayerCommand.fromMap(const {'type': 'setSubtitleDelay', 'delayMs': 1.0}),
          isA<SetSubtitleDelay>());
      expect(
          NativePlayerCommand.fromMap(const {
            'type': 'setSubtitleStyle',
            'style': {'fontSize': 16.0}
          }),
          isA<SetSubtitleStyle>());
    });

    test('C 组 4 类（解码/显示/片头片尾/截图）解析类型正确', () {
      expect(NativePlayerCommand.fromMap(const {'type': 'setDecodeMode', 'mode': 'sw'}),
          isA<SetDecodeMode>());
      expect(
          NativePlayerCommand.fromMap(
              const {'type': 'adjustDisplay', 'key': 'k', 'value': 1.0}),
          isA<AdjustDisplay>());
      expect(
          NativePlayerCommand.fromMap(
              const {'type': 'setSegmentMark', 'kind': 'intro', 'positionMs': 0}),
          isA<SetSegmentMark>());
      expect(NativePlayerCommand.fromMap(const {'type': 'takeScreenshot'}),
          isA<TakeScreenshot>());
    });
  });
}
